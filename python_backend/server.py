import asyncio
import os
import re
import shutil
import tempfile
import mimetypes
import threading
from abc import ABC, abstractmethod
from io import BytesIO
from typing import Optional, Union, Dict, Any, List
from urllib.parse import quote

import yt_dlp
from flask import Flask, request, send_file, jsonify

# Optional CORS is intentionally not required: the Flutter app talks to this
# service directly and does not need browser cross-origin access.

MAX_RAM_MB = int(os.getenv("MAX_RAM_MB", "50"))
MAX_CONCURRENT_DOWNLOADS = int(os.getenv("MAX_CONCURRENT_DOWNLOADS", "3"))
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))
COOKIE_FILE = os.getenv("YTDLP_COOKIEFILE", "").strip() or None
DEFAULT_PROXIES = [
    item.strip() for item in os.getenv("YTDLP_PROXIES", "").split(",")
    if item.strip()
]


class ProxyManager:
    def __init__(self, default_proxies: Optional[List[str]] = None):
        self.proxies = default_proxies or []
        self._index = 0

    def add_proxy(self, proxy_url: str) -> None:
        proxy_url = proxy_url.strip()
        if proxy_url and proxy_url not in self.proxies:
            self.proxies.append(proxy_url)

    def get_proxy(self) -> Optional[str]:
        if not self.proxies:
            return None
        proxy = self.proxies[self._index % len(self.proxies)]
        self._index += 1
        return proxy


class DownloadResult:
    def __init__(self, data: Union[BytesIO, str], is_file: bool, filename: str):
        self.data = data
        self.is_file = is_file
        self.filename = filename

    def cleanup(self) -> None:
        if self.is_file and isinstance(self.data, str) and os.path.exists(self.data):
            try:
                os.remove(self.data)
            except OSError:
                pass


class BaseDownloader(ABC):
    @abstractmethod
    def can_handle(self, url: str) -> bool:
        raise NotImplementedError

    @abstractmethod
    async def get_info(self, url: str, proxy: Optional[str] = None) -> Dict[str, Any]:
        raise NotImplementedError

    @abstractmethod
    async def download(
        self,
        url: str,
        format_id: Optional[str] = None,
        proxy: Optional[str] = None,
    ) -> DownloadResult:
        raise NotImplementedError


class GenericMediaStrategy(BaseDownloader):
    def __init__(
        self,
        platform_name: str,
        pattern: str,
        cookie_path: Optional[str] = None,
        max_ram_mb: int = MAX_RAM_MB,
    ):
        self.platform_name = platform_name
        self.pattern = pattern
        self.cookie_path = cookie_path
        self.max_ram_bytes = max_ram_mb * 1024 * 1024

    def can_handle(self, url: str) -> bool:
        return bool(re.search(self.pattern, url, re.IGNORECASE)) if self.pattern else True

    def _base_opts(self, proxy: Optional[str]) -> Dict[str, Any]:
        opts: Dict[str, Any] = {
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
        }
        if proxy:
            opts["proxy"] = proxy
        if self.cookie_path and os.path.exists(self.cookie_path):
            opts["cookiefile"] = self.cookie_path
        return opts

    async def get_info(self, url: str, proxy: Optional[str] = None) -> Dict[str, Any]:
        ydl_opts = self._base_opts(proxy)
        ydl_opts["skip_download"] = True
        loop = asyncio.get_running_loop()

        def _extract():
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                return ydl.extract_info(url, download=False)

        try:
            info = await loop.run_in_executor(None, _extract)
        except Exception as exc:
            # Do not manufacture media metadata on extraction failure.
            raise RuntimeError(f"استخراج اطلاعات رسانه ناموفق بود: {exc}") from exc

        formats_list = []
        seen_resolutions = set()
        for f in reversed(info.get("formats") or []):
            vcodec = f.get("vcodec", "none")
            height = f.get("height")
            if vcodec != "none" and height and height not in seen_resolutions:
                seen_resolutions.add(height)
                ext = f.get("ext") or "mp4"
                fps = f.get("fps")
                fps_str = f" ({fps}fps)" if fps and fps > 30 else ""
                formats_list.append(
                    {
                        "id": f"bestvideo[height<={int(height)}]+bestaudio/best[height<={int(height)}]",
                        "label": f"ویدیو {int(height)}p {ext.upper()}{fps_str}",
                    }
                )

        formats_list.insert(
            0,
            {
                "id": "bestvideo+bestaudio/best",
                "label": "بهترین کیفیت ویدیو / فایل (خودکار)",
            },
        )
        formats_list.append(
            {
                "id": "bestaudio/best",
                "label": "صوت تنها (MP3 / Best Audio)",
            }
        )

        duration_sec = int(info.get("duration") or 0)
        duration_str = (
            f"{duration_sec // 60}:{duration_sec % 60:02d}"
            if duration_sec
            else "نامشخص"
        )

        return {
            "platform": self.platform_name,
            "title": info.get("title") or "بدون عنوان",
            "thumbnail": info.get("thumbnail") or "",
            "duration": duration_str,
            "uploader": info.get("uploader") or info.get("extractor") or self.platform_name,
            "qualities": formats_list,
        }

    async def download(
        self,
        url: str,
        format_id: Optional[str] = None,
        proxy: Optional[str] = None,
    ) -> DownloadResult:
        selected_format = (
            format_id
            if format_id and format_id != "direct"
            else "bestvideo+bestaudio/best"
        )

        ydl_opts = self._base_opts(proxy)
        if not shutil.which("ffmpeg") and (
            "+" in selected_format or format_id == "bestaudio/best"
        ):
            raise RuntimeError(
                "برای ادغام ویدیو/صدا یا تبدیل MP3، FFmpeg باید روی سرور نصب باشد."
            )
        ydl_opts.update(
            {
                "format": selected_format,
                "outtmpl": os.path.join(
                    tempfile.gettempdir(), "%(title).50s_%(id)s.%(ext)s"
                ),
            }
        )

        if format_id == "bestaudio/best":
            ydl_opts["postprocessors"] = [
                {
                    "key": "FFmpegExtractAudio",
                    "preferredcodec": "mp3",
                    "preferredquality": "192",
                }
            ]

        loop = asyncio.get_running_loop()

        def _download():
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                if format_id == "bestaudio/best":
                    base, _ = os.path.splitext(filename)
                    mp3 = base + ".mp3"
                    if os.path.exists(mp3):
                        filename = mp3
                if not os.path.isfile(filename):
                    # Postprocessors/remuxers can change the final extension.
                    prepared_dir = os.path.dirname(filename)
                    stem = os.path.splitext(os.path.basename(filename))[0]
                    candidates = [
                        os.path.join(prepared_dir, f)
                        for f in os.listdir(prepared_dir)
                        if f.startswith(stem + ".") and os.path.isfile(os.path.join(prepared_dir, f))
                    ]
                    if candidates:
                        filename = max(candidates, key=os.path.getmtime)
                return filename

        file_path = await loop.run_in_executor(None, _download)
        if not os.path.isfile(file_path):
            raise RuntimeError("فایل خروجی yt-dlp پیدا نشد.")

        file_size = os.path.getsize(file_path)
        filename = os.path.basename(file_path)

        if file_size <= self.max_ram_bytes:
            with open(file_path, "rb") as f:
                data = BytesIO(f.read())
            data.seek(0)
            os.remove(file_path)
            return DownloadResult(data=data, is_file=False, filename=filename)

        return DownloadResult(data=file_path, is_file=True, filename=filename)


class MediaDownloadEngine:
    def __init__(self, max_concurrent_downloads: int = MAX_CONCURRENT_DOWNLOADS):
        self.proxy_manager = ProxyManager()
        self.strategies: List[BaseDownloader] = []
        # Flask runs each request in its own thread/event loop here. A
        # threading semaphore avoids binding an asyncio primitive to one
        # request loop and then reusing it from another request.
        self.semaphore = threading.BoundedSemaphore(max_concurrent_downloads)

    def register_strategy(self, strategy: BaseDownloader) -> None:
        self.strategies.append(strategy)

    def _strategy(self, url: str) -> BaseDownloader:
        for strategy in self.strategies:
            if strategy.can_handle(url):
                return strategy
        raise ValueError("پلتفرم مورد نظر پشتیبانی نمی‌شود.")

    async def get_info(self, url: str, custom_proxy: Optional[str] = None):
        proxy = custom_proxy.strip() if custom_proxy and custom_proxy.strip() else self.proxy_manager.get_proxy()
        return await self._strategy(url).get_info(url, proxy=proxy)

    async def download_media(
        self,
        url: str,
        format_id: Optional[str] = None,
        custom_proxy: Optional[str] = None,
    ):
        # The actual yt-dlp work is moved to a worker thread by the strategy.
        # The semaphore is thread-based because Flask creates a separate
        # asyncio event loop for each request via asyncio.run().
        self.semaphore.acquire()
        try:
            proxy = custom_proxy.strip() if custom_proxy and custom_proxy.strip() else self.proxy_manager.get_proxy()
            return await self._strategy(url).download(url, format_id=format_id, proxy=proxy)
        finally:
            self.semaphore.release()


app = Flask(__name__)
engine = MediaDownloadEngine()
engine.proxy_manager.proxies = DEFAULT_PROXIES

# The empty final strategy intentionally remains last, matching the original
# behavior for any URL yt-dlp understands.
engine.register_strategy(GenericMediaStrategy("YouTube", r"(youtube\.com|youtu\.be)", cookie_path=COOKIE_FILE))
engine.register_strategy(GenericMediaStrategy("Instagram", r"instagram\.com", cookie_path=COOKIE_FILE))
engine.register_strategy(GenericMediaStrategy("SoundCloud", r"soundcloud\.com", cookie_path=COOKIE_FILE))
engine.register_strategy(GenericMediaStrategy("TikTok", r"tiktok\.com", cookie_path=COOKIE_FILE))
engine.register_strategy(GenericMediaStrategy("Direct/Other", r"", cookie_path=COOKIE_FILE))


def _validate_url(url: str) -> str:
    url = (url or "").strip()
    if not re.match(r"^https?://", url, re.IGNORECASE):
        raise ValueError("فقط لینک‌های HTTP/HTTPS پشتیبانی می‌شوند.")
    return url


@app.post("/api/info")
def get_info_api():
    data = request.get_json(silent=True) or {}
    try:
        url = _validate_url(data.get("url"))
        info = asyncio.run(engine.get_info(url, custom_proxy=data.get("proxy")))
        return jsonify(info)
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.post("/api/download")
def download_api():
    data = request.get_json(silent=True) or {}
    result = None
    try:
        url = _validate_url(data.get("url"))
        result = asyncio.run(
            engine.download_media(
                url,
                format_id=data.get("format_id"),
                custom_proxy=data.get("proxy"),
            )
        )
        encoded_filename = quote(result.filename)
        guessed_mime = mimetypes.guess_type(result.filename)[0] or "application/octet-stream"
        response = send_file(
            result.data,
            as_attachment=True,
            download_name=result.filename,
            mimetype=guessed_mime,
            conditional=False,
        )
        response.headers["Content-Disposition"] = (
            f"attachment; filename*=UTF-8''{encoded_filename}"
        )

        # Cleanup only after the WSGI response is closed. Deleting a large
        # temporary file in after_this_request can race with send_file's
        # streaming iterator on some production servers.
        response.call_on_close(result.cleanup)
        return response
    except Exception as exc:
        if result is not None:
            result.cleanup()
        return jsonify({"error": str(exc)}), 400


@app.get("/health")
def health():
    return jsonify({"ok": True, "service": "Floating Downloader yt-dlp backend"})


if __name__ == "__main__":
    app.run(host=HOST, port=PORT, threaded=True)
