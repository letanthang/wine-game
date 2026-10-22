# Counter-Strike 1.6 on Windows on ARM (Surface Pro X and similar)

This package is 32-bit x86. On an ARM device such as the Surface Pro X
(Qualcomm SQ1 / SQ2), Windows runs it through its built-in x86 emulation. The
game works this way, but it can stutter. This page explains how to find out why
and how to fix it.

## Why there is no native ARM64 build

There is no ready-made Windows ARM64 build to switch to. Neither Xash3D FWGS
(the engine) nor CS16Client (the game code) publishes one: their release builds
cover Windows x86 and x64 only.

A native build would not help anyway. A Xash3D contributor tested a native
ARM64 build on a Surface Pro X and reported that OpenGL performance was worse
than with the emulated x86 build
([FWGS/xash3d-fwgs#845](https://github.com/FWGS/xash3d-fwgs/issues/845)). On
these devices the bottleneck is **OpenGL**, not the CPU emulation. The steps
below target that.

## Step 1: find out which renderer the game uses

Start the game with a log file, from a Command Prompt in this folder:

```bat
play.bat -dev 2 -log
```

Get to the main menu, then quit. The engine has written `engine.log` next to
`play.bat`. Look for the three `GL_` lines, either in Notepad or with
PowerShell:

```powershell
Select-String -Path engine.log -Pattern '^GL_(VENDOR|RENDERER|VERSION)'
```

Alternatively, press `~` in the game to open the console and scroll up with
Page Up to the same lines.

Compare what you see with this table:

| `GL_RENDERER` shows | Meaning | What to do |
| --- | --- | --- |
| `GDI Generic` (vendor `Microsoft Corporation`, version `1.1.0`) | No OpenGL driver: Windows' built-in **software** renderer draws everything on the CPU. This is the most likely cause of stutter. | Step 2 |
| `D3D12 (...Adreno...)` or similar | OpenGL is mapped onto the GPU through Direct3D 12 by the Compatibility Pack. | Already accelerated; go to Step 3 |
| a Qualcomm / Adreno name without `D3D12` | A native Qualcomm OpenGL driver is in use. | Step 3 |

The `GDI Generic` string is Windows' own. The exact `D3D12 (...)` text varies
with the driver, so match on the words rather than the full line.

## Step 2: install the OpenCL, OpenGL & Vulkan Compatibility Pack

Microsoft's **OpenCL™, OpenGL®, and Vulkan® Compatibility Pack** implements
OpenGL on top of Direct3D 12. It gives OpenGL games GPU acceleration on devices
that have a DirectX 12 driver but no OpenGL driver, which is the situation on
Qualcomm-based Windows devices.

Install it from either of these:

- the Microsoft Store:
  <https://apps.microsoft.com/detail/9nqpsl29bfff>
- or a terminal:

  ```bat
  winget install --id Microsoft.OpenCLGLVulkanCompatibilityPack
  ```

Requirements, per Microsoft:

- Windows 10 build 19041.488 or newer (any Windows 11 qualifies).
- An up-to-date DirectX 12 GPU driver. On a Surface this comes through Windows
  Update, so install pending updates, including the optional driver updates,
  first.

The pack supports OpenGL 3.3 and earlier, which covers this engine's OpenGL
renderer. Its Store listing names ARM64, x64 and x86 among the supported
architectures. Microsoft does not explicitly confirm that it serves emulated
x86 games such as this one, so treat Step 1 as the real test.

Restart the game afterwards and **repeat Step 1**. `GL_RENDERER` should no longer
say `GDI Generic`.

## Step 3: tune the rest

Try these once the renderer is right, or if Step 2 did not help. Each one is
just extra arguments to `play.bat`:

| Try | Command | Why |
| --- | --- | --- |
| Lower resolution | `play.bat -width 1280 -height 720` | The Surface Pro X screen is close to 3K. Rendering at a quarter of that is far cheaper and still looks fine for a 1999 game. |
| Windowed mode | `play.bat -windowed -width 1280 -height 720` | Avoids a display mode switch, which can be slow on these GPUs. |
| Software renderer | `play.bat -ref soft` | The engine's own CPU renderer (`ref_soft.dll`). Only worth comparing if OpenGL stays bad after Step 2: on a slow GPU path at low resolution it can be smoother. |

To go back to OpenGL after trying `-ref soft`, start once with
`play.bat -ref gl`.

In the game console (`~`) you can also set `fps_max 60` to cap the frame rate.
Steadier frame times often feel smoother than a higher frame rate that jumps
around, and the cap also saves battery.

## Why not Vulkan (considered, not recommended)

This package ships only `ref_gl.dll` (OpenGL) and `ref_soft.dll` (software).
A Vulkan renderer, `ref_vk.dll`, exists in w23's fork of the engine
([w23/xash3d-fwgs](https://github.com/w23/xash3d-fwgs), branch `vulkan`). The
fork is still active and its `continuous-vulkan` release includes Windows x86
and x64 builds. It is not a good fit for the Surface Pro X:

- **No ray tracing on this GPU.** The fork's main feature is path-traced
  lighting, and the fork ships lighting data for a few CS maps (`cs_747`,
  `cs_assault`, `cs_italy`, `de_dust2`, ...). Its ray tracing mode needs
  `VK_KHR_acceleration_structure`, `VK_KHR_ray_tracing_pipeline` and
  `VK_KHR_ray_query` (`ref/vk/vulkan/VDevice.c`), and it also needs the 64-bit
  build. The Adreno 685 / 690 in the SQ1 / SQ2 has no ray tracing hardware.
  Qualcomm added it with later GPUs (Adreno 740 on phones, Adreno X1 in
  Snapdragon X laptops).
- **The non-ray-traced mode is slower than OpenGL.** The fork's README says so
  itself: there is no visibility culling yet.
- **Vulkan on Windows on ARM is itself a translation layer.** Through the
  Compatibility Pack from Step 2, Vulkan runs on **Dozen** (Mesa's Vulkan on
  Direct3D 12). One user test with another game measured roughly half the frame
  rate of a native Vulkan driver. On top of that, this game already runs under
  x86 emulation.

Stay on `ref_gl` together with the Compatibility Pack. Revisit Vulkan only on a
Snapdragon X device. Before trying it there, check with
[Vulkan Hardware Capability Viewer](https://vulkan.gpuinfo.org/download.php)
that the driver lists both `VK_KHR_ray_tracing_pipeline` and
`VK_KHR_ray_query`. Adreno X1 is confirmed to support ray queries. Support for
the ray tracing pipeline extension was not confirmed as of 2026-10-22.

## If it is still not smooth

Collect the following and report back:

- the three `GL_` lines from Step 1, before and after Step 2;
- `winver` output (Windows version and build);
- which of the Step 3 options changed anything.

## Status

Written 2026-10-14 from upstream sources (the Xash3D issue above, the engine's
own logging code, Microsoft's Store listing and announcement). **Not yet
verified on a Surface Pro X.** The table in Step 1 and the effect of Step 2 are
expectations until someone runs them on the device. The Vulkan section was
added 2026-10-22 from the w23 fork's source and README, plus the sources
below, and was also not tested on the device.

Sources:

- [Windows ARM64/ARM32 build — FWGS/xash3d-fwgs#845](https://github.com/FWGS/xash3d-fwgs/issues/845)
- [OpenCL™, OpenGL®, and Vulkan® Compatibility Pack — Microsoft Store](https://apps.microsoft.com/detail/9nqpsl29bfff)
- [Announcing the OpenCL™ and OpenGL® Compatibility Pack for Windows 10 on ARM — DirectX Developer Blog](https://devblogs.microsoft.com/directx/announcing-the-opencl-and-opengl-compatibility-pack-for-windows-10-on-arm/)
- [Vulkan Ray Tracing fork of Xash3D FWGS — w23/xash3d-fwgs](https://github.com/w23/xash3d-fwgs)
- [Snapdragon X architecture deep dive, Adreno X1 — AnandTech](https://at-web1.www.anandtech.com/show/21445/qualcomm-snapdragon-x-architecture-deep-dive/3)
- ["Dozen" merged into Mesa — Phoronix](https://www.phoronix.com/news/Vulkan-On-Direct3D-12-Dzn-Merge)
- [Dzn vs native Vulkan on Windows on ARM — user report](https://devinthreethousand.substack.com/p/driver-tweak-for-windows-arm-could)
