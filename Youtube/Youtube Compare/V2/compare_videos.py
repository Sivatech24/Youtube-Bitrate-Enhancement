import ffmpeg
import cv2
import numpy as np
from skimage.metrics import structural_similarity as ssim

def get_video_info(video_path):
    """Extracts basic video info (resolution, frame rate, bitrate) using ffmpeg."""
    probe = ffmpeg.probe(video_path, v='error', select_streams='v:0', show_entries='stream=width,height,codec_name,codec_long_name,r_frame_rate,bit_rate')
    stream = probe['streams'][0]
    
    width = stream['width']
    height = stream['height']
    frame_rate = eval(stream['r_frame_rate'])  # Convert to float
    codec = stream['codec_long_name']
    bitrate = int(stream['bit_rate']) if 'bit_rate' in stream else None
    
    return {
        'width': width,
        'height': height,
        'frame_rate': frame_rate,
        'codec': codec,
        'bitrate': bitrate
    }

def calculate_psnr(original, compressed):
    """Calculate PSNR (Peak Signal to Noise Ratio) between two frames."""
    mse = np.mean((original - compressed) ** 2)
    if mse == 0:
        return 100
    PIXEL_MAX = 255.0
    return 20 * np.log10(PIXEL_MAX / np.sqrt(mse))

def compare_videos(original_video, uploaded_video):
    """Compare two videos by analyzing PSNR, SSIM, and basic properties."""
    
    # Get basic video info
    original_info = get_video_info(original_video)
    uploaded_info = get_video_info(uploaded_video)
    
    print("Original Video Info:", original_info)
    print("Uploaded Video Info:", uploaded_info)
    
    # Check for resolution and frame rate match
    if original_info['width'] != uploaded_info['width'] or original_info['height'] != uploaded_info['height']:
        print("Warning: Resolutions don't match between the two videos.")
    
    if original_info['frame_rate'] != uploaded_info['frame_rate']:
        print("Warning: Frame rates don't match between the two videos.")
    
    # Compare video quality frame by frame (using PSNR and SSIM)
    cap_original = cv2.VideoCapture(original_video)
    cap_uploaded = cv2.VideoCapture(uploaded_video)
    
    frame_count = 0
    total_psnr = 0
    total_ssim = 0
    frame_comparisons = 0
    
    while True:
        ret_original, frame_original = cap_original.read()
        ret_uploaded, frame_uploaded = cap_uploaded.read()
        
        if not ret_original or not ret_uploaded:
            break
        
        # Convert frames to grayscale for SSIM calculation
        gray_original = cv2.cvtColor(frame_original, cv2.COLOR_BGR2GRAY)
        gray_uploaded = cv2.cvtColor(frame_uploaded, cv2.COLOR_BGR2GRAY)
        
        # Calculate PSNR for the current frame
        psnr_value = calculate_psnr(gray_original, gray_uploaded)
        total_psnr += psnr_value
        
        # Calculate SSIM for the current frame
        ssim_value, _ = ssim(gray_original, gray_uploaded, full=True)
        total_ssim += ssim_value
        
        frame_comparisons += 1
        frame_count += 1
    
    cap_original.release()
    cap_uploaded.release()
    
    # Compute average PSNR and SSIM over all frames
    avg_psnr = total_psnr / frame_comparisons if frame_comparisons > 0 else 0
    avg_ssim = total_ssim / frame_comparisons if frame_comparisons > 0 else 0
    
    print(f"\nAverage PSNR: {avg_psnr:.2f} dB")
    print(f"Average SSIM: {avg_ssim:.4f}")
    
    return {
        'avg_psnr': avg_psnr,
        'avg_ssim': avg_ssim,
        'original_info': original_info,
        'uploaded_info': uploaded_info
    }

# Paths to your video files
original_video_path = 'path_to_original_video.mp4'
uploaded_video_path = 'path_to_uploaded_video.mp4'

# Compare the videos
compare_videos(original_video_path, uploaded_video_path)
