import os
import ctypes
import subprocess
from tkinter import Tk, Frame, Label, Canvas, Scrollbar
from PIL import Image, ImageTk
from colorthief import ColorThief

WALLPAPER_DIR = r"D:\Pictures\Wallpapers and other\Desktop Wallpapers"
CSS_FILE = r"C:\Users\Arnav\.config\yasb\styles.css"

SPI_SETDESKWALLPAPER = 20

# =======================
# WALLPAPER
# =======================
def set_wallpaper(path):
    ctypes.windll.user32.SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, path, 3)

# =======================
# COLOR EXTRACTION
# =======================
def rgb_to_hex(rgb):
    return '#%02x%02x%02x' % rgb


def brighten(rgb, amount=25):
    return tuple(min(255, c + amount) for c in rgb)


def darken(rgb, amount=25):
    return tuple(max(0, c - amount) for c in rgb)


def update_yasb_colors(image_path):
    try:
        color_thief = ColorThief(image_path)

        dominant = color_thief.get_color(quality=1)

        accent = rgb_to_hex(brighten(dominant, 20))
        surface = rgb_to_hex(darken(dominant, 60))
        crust = rgb_to_hex(darken(dominant, 90))

        with open(CSS_FILE, 'r', encoding='utf-8') as f:
            css = f.read()

        import re

        css = re.sub(r'--dynamic-accent:.*?;', f'--dynamic-accent: {accent};', css)
        css = re.sub(r'--dynamic-surface:.*?;', f'--dynamic-surface: {surface};', css)
        css = re.sub(r'--dynamic-crust:.*?;', f'--dynamic-crust: {crust};', css)

        with open(CSS_FILE, 'w', encoding='utf-8') as f:
            f.write(css)

        subprocess.run([
            'powershell',
            '-Command',
            'Stop-Process -Name yasb -Force; Start-Process yasb'
        ], shell=True)

    except Exception as e:
        print("Theme sync failed:", e)

# =======================
# ROOT
# =======================
root = Tk()

screen_h = root.winfo_screenheight()
panel_w = 340

root.geometry(f"{panel_w}x{screen_h}+0+0")

root.overrideredirect(True)
root.attributes("-topmost", True)

root.configure(bg="#101018")
root.wm_attributes("-alpha", 0.97)

# =======================
# CLOSE
# =======================
def close_panel(event=None):
    root.destroy()

root.bind("<Escape>", close_panel)
root.bind("<FocusOut>", close_panel)

# =======================
# MAIN
# =======================
main = Frame(root, bg="#101018")
main.pack(fill="both", expand=True)

# =======================
# SCROLL AREA
# =======================
canvas = Canvas(
    main,
    bg="#101018",
    highlightthickness=0,
    bd=0
)

scrollbar = Scrollbar(
    main,
    orient="vertical",
    command=canvas.yview
)

scroll_frame = Frame(canvas, bg="#101018")

scroll_frame.bind(
    "<Configure>",
    lambda e: canvas.configure(
        scrollregion=canvas.bbox("all")
    )
)

canvas.create_window(
    (0, 0),
    window=scroll_frame,
    anchor="nw",
    width=panel_w
)

canvas.configure(yscrollcommand=scrollbar.set)

canvas.pack(side="left", fill="both", expand=True)
scrollbar.pack(side="right", fill="y")

canvas.bind_all(
    "<MouseWheel>",
    lambda e: canvas.yview_scroll(int(-1 * (e.delta / 120)), "units")
)

# =======================
# LOAD WALLPAPERS
# =======================
images = []

files = [
    f for f in os.listdir(WALLPAPER_DIR)
    if f.lower().endswith((".png", ".jpg", ".jpeg"))
]

for file in files:

    full_path = os.path.join(WALLPAPER_DIR, file)

    try:
        img = Image.open(full_path)
        img = img.resize((300, 170))

        tk_img = ImageTk.PhotoImage(img)

        card = Frame(
            scroll_frame,
            bg="#181825",
            highlightthickness=1,
            highlightbackground="#313244"
        )

        label = Label(
            card,
            image=tk_img,
            bg="#181825",
            cursor="hand2",
            bd=0
        )

        def handler(p=full_path):
            set_wallpaper(p)
            update_yasb_colors(p)
            root.destroy()

        label.bind(
            "<Button-1>",
            lambda e, p=full_path: handler(p)
        )

        def on_enter(e, c=card):
            c.configure(highlightbackground="#89b4fa")

        def on_leave(e, c=card):
            c.configure(highlightbackground="#313244")

        card.bind("<Enter>", on_enter)
        card.bind("<Leave>", on_leave)

        label.pack(padx=6, pady=6)
        card.pack(pady=10, padx=12)

        images.append(tk_img)

    except Exception as e:
        print(f"Failed: {file} -> {e}")

root.after(100, lambda: root.focus_force())

root.mainloop()