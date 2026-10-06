import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
bg = Image.new("RGBA", im.size, (24, 24, 26, 255))
bg.alpha_composite(im)
bg.convert("RGB").resize((im.width // 2, im.height // 2)).save(sys.argv[2])
