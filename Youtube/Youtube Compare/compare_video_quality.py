import cv2
import numpy as np
from skimage.metrics import structural_similarity as ssim
from tqdm import tqdm
import os

def calculate_psnr(original, compressed):
    """Calculate PSNR between two images."""
    mse = np.mean((original - compressed) ** 2)
    if mse == 0:
        return 100  # PSNR is infinite if no difference
    max_pixel = 255.0
    psnr = 20 * np.log10(max_pixel / np.sqrt(mse))
    return psnr

def calculate_ssim(original, compressed):
    """Calculate SSIM between two images."""
    return ssim(original, compressed, data_range=compressed.max() - compressed.min())

def extract_frames(video_path):
    """Extract frames from the video."""
    video_capture = cv2.VideoCapture(video_path)
    frames = []
    while True:
        ret, frame = video_capture.read()
        if not ret:
            break
        frames.append(frame)
    video_capture.release()
    return frames

def compare_videos(original_video_path, uploaded_video_path):
    """Compare videos using PSNR and SSIM."""
    # Extract frames from both videos
    print("Extracting frames from the original video...")
    original_frames = extract_frames(original_video_path)
    print("Extracting frames from the uploaded video...")
    uploaded_frames = extract_frames(uploaded_video_path)
    
    # Make sure both videos have the same number of frames
    if len(original_frames) != len(uploaded_frames):
        raise ValueError("Videos have different number of frames!")
    
    total_psnr = 0
    total_ssim = 0
    frame_count = len(original_frames)
    
    # Initialize the progress bar
    for orig_frame, upload_frame in tqdm(zip(original_frames, uploaded_frames), total=frame_count, desc="Comparing frames", unit="frame"):
        # Convert frames to grayscale
        orig_gray = cv2.cvtColor(orig_frame, cv2.COLOR_BGR2GRAY)
        upload_gray = cv2.cvtColor(upload_frame, cv2.COLOR_BGR2GRAY)
        
        # Calculate PSNR and SSIM for the current frame
        psnr_value = calculate_psnr(orig_gray, upload_gray)
        ssim_value = calculate_ssim(orig_gray, upload_gray)

        total_psnr += psnr_value
        total_ssim += ssim_value

    # Calculate average PSNR and SSIM
    average_psnr = total_psnr / frame_count if frame_count > 0 else 0
    average_ssim = total_ssim / frame_count if frame_count > 0 else 0

    print(f"\nAverage PSNR: {average_psnr:.2f} dB")
    print(f"Average SSIM: {average_ssim:.4f}")

if __name__ == "__main__":
    original_video_path = input("Enter the path to the original video: ")
    uploaded_video_path = input("Enter the path to the uploaded video: ")

    try:
        compare_videos(original_video_path, uploaded_video_path)
    except Exception as e:
        print(f"Error: {e}")
