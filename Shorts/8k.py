import yt_dlp

def download_vertical_video(url):
    # yt-dlp options
    ydl_opts = {
        'format': 'bestvideo+bestaudio/best',  # Download the best video and audio available
        'outtmpl': '%(title)s.%(ext)s',  # Output file template
        'noplaylist': True,  # Avoid downloading playlists
        'postprocessors': [{
            'key': 'FFmpegVideoConvertor',  # Use FFmpeg for additional processing (if needed)
            'preferedformat': 'mp4',  # Convert to MP4 format (you can change to other formats if necessary)
        }],
        'ffmpeg_location': 'C:/ffmpeg/bin',  # Path to ffmpeg executable (if not in PATH)
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        try:
            # Start downloading the video
            ydl.download([url])
            print("Download and processing completed successfully!")
        except Exception as e:
            print(f"Error occurred: {e}")

# Replace this URL with the actual vertical video URL you want to download
video_url = "https://youtube.com/shorts/FmfYK-Hq5XE"
download_vertical_video(video_url)
