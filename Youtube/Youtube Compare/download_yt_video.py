import yt_dlp

def download_video(url, download_path='.'):
    """Download a YouTube video with 4K/8K resolution using yt-dlp."""
    try:
        # yt-dlp options
        ydl_opts = {
            'format': 'bestvideo+bestaudio/best',  # Best video and audio combined
            'outtmpl': f'{download_path}/%(title)s.%(ext)s',  # Save as title.extension in the given path
            'noplaylist': True,  # Only download a single video, not a playlist
            'merge_output_format': 'mp4',  # Merge audio and video to MP4 if they are separate
        }

        # Create a yt-dlp object with the options
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # Download the video
            print(f"Downloading video from: {url}")
            ydl.download([url])

        print("Download completed successfully!")

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    # URL of the YouTube video to download
    video_url = input("Enter the YouTube video URL: ")
    
    # Optional: Specify the download directory (default is the current directory)
    download_directory = input("Enter the download path (or press Enter to use current directory): ")
    
    # If no path is provided, use the current directory
    if not download_directory:
        download_directory = '.'

    # Call the function to download the video
    download_video(video_url, download_path=download_directory)
