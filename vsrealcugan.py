"""
VapourSynth Real-CUGAN Wrapper
Provides Real-CUGAN upscaling functionality for VapourSynth
Optimized for animation content like Futurama
"""

import os
import sys
import tempfile
import subprocess
import numpy as np
import vapoursynth as vs
from PIL import Image
from typing import Optional

core = vs.core

class RealCUGAN:
    """Real-CUGAN upscaler for VapourSynth"""

    def __init__(self, device_id: int = 0, model_path: str = "", scale: int = 4,
                 tile: int = 256, sync: int = 0, tta_mode: int = 0):
        """
        Initialize Real-CUGAN upscaler

        Args:
            device_id: GPU device ID
            model_path: Path to Real-CUGAN model
            scale: Upscaling factor (2 or 4)
            tile: Tile size for processing
            sync: Sync mode (not used in this implementation)
            tta_mode: Test-time augmentation mode
        """
        self.device_id = device_id
        self.model_path = model_path
        self.scale = scale
        self.tile = tile
        self.tta_mode = tta_mode

        # Determine model name and scale from path
        if "up2x" in model_path or "2x" in model_path:
            self.scale = 2
        elif "up4x" in model_path or "4x" in model_path:
            self.scale = 4

        # Determine noise level from model name
        if "denoise3x" in model_path:
            self.noise = 3
        elif "denoise1x" in model_path:
            self.noise = 1
        else:
            self.noise = -1  # No denoising

        print(f"[Real-CUGAN] Initialized with scale={self.scale}, noise={self.noise}, tile={self.tile}")

    def __call__(self, clip: vs.VideoNode) -> vs.VideoNode:
        """Process VapourSynth clip with Real-CUGAN"""

        def process_frame(n: int, f: vs.VideoFrame) -> vs.VideoFrame:
            """Process individual frame"""
            try:
                # Convert VapourSynth frame to numpy array
                img_array = self._vs_frame_to_array(f)

                # Process with Real-CUGAN
                upscaled_array = self._process_image_array(img_array)

                # Convert back to VapourSynth frame
                return self._array_to_vs_frame(upscaled_array, f)

            except Exception as e:
                print(f"[Real-CUGAN] Error processing frame {n}: {e}")
                # Return original frame scaled with basic method as fallback
                return self._fallback_upscale(f)

        # Create output clip with new dimensions
        new_width = clip.width * self.scale
        new_height = clip.height * self.scale

        # Process clip
        return core.std.ModifyFrame(clip, clip, process_frame)

    def _vs_frame_to_array(self, frame: vs.VideoFrame) -> np.ndarray:
        """Convert VapourSynth frame to numpy array (RGB)"""
        # Get frame planes
        r_plane = np.array(frame.get_read_array(0), copy=False)
        g_plane = np.array(frame.get_read_array(1), copy=False)
        b_plane = np.array(frame.get_read_array(2), copy=False)

        # Stack planes into RGB array
        rgb_array = np.stack([r_plane, g_plane, b_plane], axis=-1)

        # Convert from float to uint8 if needed
        if rgb_array.dtype == np.float32:
            rgb_array = (rgb_array * 255).astype(np.uint8)

        return rgb_array

    def _array_to_vs_frame(self, array: np.ndarray, original_frame: vs.VideoFrame) -> vs.VideoFrame:
        """Convert numpy array back to VapourSynth frame"""
        # Ensure array is uint8
        if array.dtype != np.uint8:
            array = (array * 255).astype(np.uint8)

        # Create new frame with upscaled dimensions
        new_height, new_width = array.shape[:2]

        # Split RGB channels
        r_plane = array[:, :, 0]
        g_plane = array[:, :, 1]
        b_plane = array[:, :, 2]

        # Create new clip with proper dimensions
        blank = core.std.BlankClip(
            width=new_width,
            height=new_height,
            format=original_frame.format,
            length=1
        )

        # Get frame and set data
        new_frame = blank.get_frame(0)

        # Copy plane data
        np.copyto(np.array(new_frame.get_write_array(0), copy=False), r_plane)
        np.copyto(np.array(new_frame.get_write_array(1), copy=False), g_plane)
        np.copyto(np.array(new_frame.get_write_array(2), copy=False), b_plane)

        return new_frame

    def _process_image_array(self, img_array: np.ndarray) -> np.ndarray:
        """Process image array with Real-CUGAN via subprocess"""

        # Use Real-CUGAN command line tool
        try:
            import realcugan
            # Try to use Real-CUGAN Python API if available
            return self._process_with_python_api(img_array)
        except ImportError:
            # Fallback to command line tool
            return self._process_with_cli(img_array)

    def _process_with_python_api(self, img_array: np.ndarray) -> np.ndarray:
        """Process using Real-CUGAN Python API"""
        try:
            import torch
            from PIL import Image

            # Convert to PIL Image
            pil_img = Image.fromarray(img_array, 'RGB')

            # Use Real-CUGAN model (this would need the actual Real-CUGAN implementation)
            # For now, we'll use a placeholder that calls the CLI
            return self._process_with_cli(img_array)

        except Exception as e:
            print(f"[Real-CUGAN] Python API failed: {e}")
            return self._process_with_cli(img_array)

    def _process_with_cli(self, img_array: np.ndarray) -> np.ndarray:
        """Process using Real-CUGAN command line tool"""

        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = os.path.join(temp_dir, "input.png")
            output_path = os.path.join(temp_dir, "output.png")

            # Save input image
            pil_img = Image.fromarray(img_array, 'RGB')
            pil_img.save(input_path)

            # Construct Real-CUGAN command
            cmd = [
                "python3", "/usr/local/lib/realcugan/upcunet_v3.py",
                "-i", input_path,
                "-o", output_path,
                "-s", str(self.scale),
                "-n", str(self.noise),
                "-t", str(self.tile)
            ]

            if self.tta_mode:
                cmd.extend(["-x"])

            # Add GPU specification
            if self.device_id >= 0:
                cmd.extend(["-g", str(self.device_id)])

            try:
                # Run Real-CUGAN
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)

                if result.returncode != 0:
                    print(f"[Real-CUGAN] CLI failed: {result.stderr}")
                    return self._fallback_upscale_array(img_array)

                # Load output image
                if os.path.exists(output_path):
                    output_img = Image.open(output_path)
                    return np.array(output_img)
                else:
                    print("[Real-CUGAN] Output file not created")
                    return self._fallback_upscale_array(img_array)

            except subprocess.TimeoutExpired:
                print("[Real-CUGAN] Processing timeout")
                return self._fallback_upscale_array(img_array)
            except Exception as e:
                print(f"[Real-CUGAN] CLI processing failed: {e}")
                return self._fallback_upscale_array(img_array)

    def _fallback_upscale_array(self, img_array: np.ndarray) -> np.ndarray:
        """Fallback upscaling using PIL"""
        pil_img = Image.fromarray(img_array, 'RGB')
        new_size = (pil_img.width * self.scale, pil_img.height * self.scale)
        upscaled_img = pil_img.resize(new_size, Image.LANCZOS)
        return np.array(upscaled_img)

    def _fallback_upscale(self, frame: vs.VideoFrame) -> vs.VideoFrame:
        """Fallback upscaling for VapourSynth frame"""
        # Convert to array, upscale, convert back
        img_array = self._vs_frame_to_array(frame)
        upscaled_array = self._fallback_upscale_array(img_array)
        return self._array_to_vs_frame(upscaled_array, frame)


def create_real_cugan_function():
    """Create Real-CUGAN function for VapourSynth"""

    def real_cugan(clip: vs.VideoNode, model_path: str = "", scale: int = 4,
                   tile: int = 256, device_id: int = 0, noise: int = -1,
                   tta_mode: int = 0) -> vs.VideoNode:
        """
        Real-CUGAN upscaling function for VapourSynth

        Args:
            clip: Input video clip
            model_path: Path to Real-CUGAN model
            scale: Upscaling factor (2 or 4)
            tile: Tile size for processing
            device_id: GPU device ID
            noise: Noise reduction level (-1, 0, 1, 2, 3)
            tta_mode: Test-time augmentation
        """

        if not model_path:
            # Use default model based on scale
            if scale == 2:
                model_path = "/models/realcugan/Real-CUGAN_up2x-latest-denoise3x.pth"
            else:
                model_path = "/models/realcugan/Real-CUGAN_up4x-latest-conservative.pth"

        upscaler = RealCUGAN(
            device_id=device_id,
            model_path=model_path,
            scale=scale,
            tile=tile,
            tta_mode=tta_mode
        )

        return upscaler(clip)

    return real_cugan


# Register function with VapourSynth
if __name__ == "__main__":
    # This allows the module to be imported and used
    pass
else:
    # Register the function when imported
    try:
        core.realcugan = create_real_cugan_function()
        print("[Real-CUGAN] VapourSynth wrapper registered successfully")
    except Exception as e:
        print(f"[Real-CUGAN] Failed to register VapourSynth wrapper: {e}")