import cv2
import numpy as np
from skimage.metrics import structural_similarity as ssim

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

def compare_videos(original_video_path, uploaded_video_path):
    """Compare two videos using PSNR and SSIM."""
    original_video = cv2.VideoCapture(original_video_path)
    uploaded_video = cv2.VideoCapture(uploaded_video_path)

    # Check if the videos opened successfully
    if not original_video.isOpened() or not uploaded_video.isOpened():
        print("Error: Could not open video files.")
        return

    frame_count = 0
    total_psnr = 0
    total_ssim = 0
    while True:
        ret_original, original_frame = original_video.read()
        ret_uploaded, uploaded_frame = uploaded_video.read()

        if not ret_original or not ret_uploaded:
            break

        # Resize the frames to the same size (if needed)
        uploaded_frame_resized = cv2.resize(uploaded_frame, (original_frame.shape[1], original_frame.shape[0]))

        # Convert frames to grayscale for SSIM (optional, but faster)
        original_gray = cv2.cvtColor(original_frame, cv2.COLOR_BGR2GRAY)
        uploaded_gray = cv2.cvtColor(uploaded_frame_resized, cv2.COLOR_BGR2GRAY)

        # Calculate PSNR and SSIM
        psnr_value = calculate_psnr(original_gray, uploaded_gray)
        ssim_value = calculate_ssim(original_gray, uploaded_gray)

        total_psnr += psnr_value
        total_ssim += ssim_value
        frame_count += 1

    # Average PSNR and SSIM
    average_psnr = total_psnr / frame_count if frame_count > 0 else 0
    average_ssim = total_ssim / frame_count if frame_count > 0 else 0

    print(f"Average PSNR: {average_psnr:.2f} dB")
    print(f"Average SSIM: {average_ssim:.4f}")

    original_video.release()
    uploaded_video.release()

if __name__ == "__main__":
    # Paths to the original and uploaded videos
    original_video_path = input("Enter the path to the original video: ")
    uploaded_video_path = input("Enter the path to the uploaded video: ")

    # Compare videos
    compare_videos(original_video_path, uploaded_video_path)
