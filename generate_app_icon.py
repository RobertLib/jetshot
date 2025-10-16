#!/usr/bin/env python3
"""
Jetshot App Icon Generator
Creates an icon with a spaceship and starfield background in game style
"""

from PIL import Image, ImageDraw, ImageFilter
import random
import os
import json

def create_starfield_background(size):
    """Creates starfield background with gradient exactly like in the game"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Exact gradient colors from StarfieldHelper.swift
    # Top: UIColor(red: 0.05, green: 0.02, blue: 0.15, alpha: 1.0) = (13, 5, 38)
    # Second: UIColor(red: 0.02, green: 0.05, blue: 0.12, alpha: 1.0) = (5, 13, 31)
    # Third: UIColor(red: 0.01, green: 0.02, blue: 0.08, alpha: 1.0) = (3, 5, 20)
    # Bottom: UIColor(red: 0.0, green: 0.0, blue: 0.03, alpha: 1.0) = (0, 0, 8)

    for y in range(size):
        ratio = y / size

        if ratio < 0.3:
            # Top to second color
            local_ratio = ratio / 0.3
            r = int(13 * (1 - local_ratio) + 5 * local_ratio)
            g = int(5 * (1 - local_ratio) + 13 * local_ratio)
            b = int(38 * (1 - local_ratio) + 31 * local_ratio)
        elif ratio < 0.7:
            # Second to third color
            local_ratio = (ratio - 0.3) / 0.4
            r = int(5 * (1 - local_ratio) + 3 * local_ratio)
            g = int(13 * (1 - local_ratio) + 5 * local_ratio)
            b = int(31 * (1 - local_ratio) + 20 * local_ratio)
        else:
            # Third to bottom color
            local_ratio = (ratio - 0.7) / 0.3
            r = int(3 * (1 - local_ratio) + 0 * local_ratio)
            g = int(5 * (1 - local_ratio) + 0 * local_ratio)
            b = int(20 * (1 - local_ratio) + 8 * local_ratio)

        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    return img, draw

def add_nebulae(img, size):
    """Adds nebula clouds like in the game"""
    # Create a few subtle nebula clouds with proper alpha blending
    for _ in range(3):  # Increased from 2 to 3 nebulae
        center_x = random.randint(int(size * 0.2), int(size * 0.8))
        center_y = random.randint(int(size * 0.2), int(size * 0.8))

        # Random nebula color type from the game
        color_type = random.choice([
            # Purple nebula
            [(153, 76, 204), (76, 51, 127), (51, 25, 76)],
            # Blue nebula
            [(51, 127, 230), (25, 76, 153), (13, 38, 76)],
            # Cyan nebula
            [(76, 204, 230), (51, 127, 153), (25, 64, 76)]
        ])

        # Draw multiple overlapping circles for organic nebula look
        for layer in range(3):
            radius = random.randint(int(size * 0.2), int(size * 0.35))  # Larger nebulae
            offset_x = random.randint(-int(size * 0.08), int(size * 0.08))
            offset_y = random.randint(-int(size * 0.08), int(size * 0.08))

            color = color_type[layer]
            alpha = int(60 * (1 - layer * 0.3))  # More visible (doubled from 30)

            # Create a temporary image for this nebula layer with alpha
            temp_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            temp_draw = ImageDraw.Draw(temp_img)
            temp_draw.ellipse([
                center_x + offset_x - radius,
                center_y + offset_y - radius,
                center_x + offset_x + radius,
                center_y + offset_y + radius
            ], fill=(*color, alpha))

            # Blur the nebula for soft edges
            temp_img = temp_img.filter(ImageFilter.GaussianBlur(radius=max(8, int(size * 0.08))))

            # Composite the nebula onto the main image
            img.alpha_composite(temp_img)

    return img

def add_stars(draw, size, num_stars):
    """Adds stars with varied sizes and colors exactly like in the game"""
    # Star colors from the game - white, blue-white, yellow-white variations
    for _ in range(num_stars):
        x = random.randint(0, size)
        y = random.randint(0, size)

        # Variable star sizes for depth (from StarfieldHelper.swift)
        # particleScale = 0.2, particleScaleRange = 0.4
        star_scale = random.uniform(0.1, 0.6)  # Tiny to large stars
        star_size = max(1, int(star_scale * size * 0.015))

        # Variable brightness (particleAlpha = 0.6, particleAlphaRange = 0.3)
        brightness = random.uniform(0.4, 1.0)  # Increased from 0.3-0.9

        # Star color variations (white, blue-white, yellow-white, red-white)
        base_brightness = int(242 * brightness)  # 0.95 * 255
        red_var = random.uniform(-0.3, 0.3)
        green_var = random.uniform(-0.2, 0.2)
        blue_var = random.uniform(-0.4, 0.4)

        r = int(min(255, max(0, base_brightness + red_var * 255)))
        g = int(min(255, max(0, base_brightness + green_var * 255)))
        b = int(min(255, max(0, base_brightness + blue_var * 255)))

        # Draw star with glow
        if star_size >= 3:
            # Large star with glow effect
            glow_size = star_size + 2
            draw.ellipse([x - glow_size, y - glow_size, x + glow_size, y + glow_size],
                        fill=(r//3, g//3, b//3))
            draw.ellipse([x - star_size, y - star_size, x + star_size, y + star_size],
                        fill=(r, g, b))
            draw.ellipse([x - star_size//2, y - star_size//2, x + star_size//2, y + star_size//2],
                        fill=(255, 255, 255))
        elif star_size == 2:
            draw.ellipse([x - star_size, y - star_size, x + star_size, y + star_size],
                        fill=(r, g, b))
            draw.point((x, y), fill=(255, 255, 255))
        else:
            draw.point((x, y), fill=(r, g, b))

def add_multi_layer_glow(draw, path, center_x, center_y, scale, color, blur_layers=3):
    """Adds multi-layer glow effect like GlowHelper.addEnhancedGlow"""
    # From GlowHelper.swift - 3 layer glow with scales 1.12, 1.35, 1.6
    # and alphas 0.4, 0.25, 0.15 with blend mode .add

    glow_params = [
        (1.6, 0.15),   # Outer soft glow (drawn first, bottom layer)
        (1.35, 0.25),  # Middle glow
        (1.12, 0.4),   # Inner bright core
    ]

    for glow_scale, alpha in glow_params:
        # Scale the path
        glow_path = [(center_x + (x - center_x) * glow_scale,
                     center_y + (y - center_y) * glow_scale)
                    for x, y in path]

        # Calculate glow color with alpha (simulating .add blend mode)
        glow_color = (
            int(color[0] * alpha),
            int(color[1] * alpha),
            int(color[2] * alpha)
        )

        draw.polygon(glow_path, fill=glow_color, outline=None)

def draw_spaceship(img, draw, size):
    """Draws spaceship exactly like in the game with proper colors and glow"""
    # Make spaceship much bigger - take up more of the icon
    scale = size / 60  # Increased from 80 to 60 for even bigger ship

    # Center the spaceship perfectly
    cx = size / 2
    cy = size / 2  # Perfectly centered

    # Exact spaceship path from Player.swift
    spaceship_path = [
        (0, 18),           # Nose
        (-5, 8),           # Upper left fuselage
        (-4, -2),          # Lower left fuselage
        (-12, -8),         # Left wing tip
        (-10, -12),        # Left wing back
        (-5, -10),         # Left wing inner
        (-6, -18),         # Left engine bottom
        (-3, -18),         # Left engine inner
        (-3, -10),         # Back to fuselage
        (0, -8),           # Center back
        (3, -10),          # Right side
        (3, -18),          # Right engine inner
        (6, -18),          # Right engine bottom
        (5, -10),          # Right engine outer
        (10, -12),         # Right wing back
        (12, -8),          # Right wing tip
        (4, -2),           # Right wing inner
        (5, 8),            # Upper right fuselage
    ]

    # Scale and translate points
    scaled_path = [(cx + x * scale, cy - y * scale) for x, y in spaceship_path]

    # Exact colors from Player.swift
    # fillColor = UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0) = (51, 153, 230)
    # strokeColor = UIColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 1.0) = (102, 230, 255)
    main_fill_color = (51, 153, 230)
    main_stroke_color = (102, 230, 255)

    # Glow color from Player.swift: UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1.0)
    glow_color = (51, 204, 255)

    # Add the enhanced glow effect (3 layers like in GlowHelper)
    add_multi_layer_glow(draw, scaled_path, cx, cy, scale, glow_color, blur_layers=3)

    # Main spaceship body
    stroke_width = max(2, int(scale * 0.8))  # lineWidth = 2.5 in game
    draw.polygon(scaled_path, fill=main_fill_color, outline=main_stroke_color, width=stroke_width)

    # Add cockpit detail
    # From Player.swift: SKShapeNode(circleOfRadius: 3)
    # fillColor = UIColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.9) = (77, 204, 255)
    # strokeColor = UIColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 1.0) = (153, 255, 255)
    cockpit_radius = 3 * scale
    cockpit_y = cy - 8 * scale
    cockpit_fill = (77, 204, 255)
    cockpit_stroke = (153, 255, 255)

    # Outer cockpit
    draw.ellipse([
        cx - cockpit_radius, cockpit_y - cockpit_radius,
        cx + cockpit_radius, cockpit_y + cockpit_radius
    ], fill=cockpit_fill, outline=cockpit_stroke, width=max(1, int(scale * 0.5)))

    # Inner bright center
    inner_radius = cockpit_radius * 0.6
    draw.ellipse([
        cx - inner_radius, cockpit_y - inner_radius,
        cx + inner_radius, cockpit_y + inner_radius
    ], fill=(200, 240, 255))

    # Engine glow effects
    # From Player.swift: UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.8) = (0, 204, 255)
    engine_color = (0, 204, 255)
    engine_width = 2.5 * scale
    engine_height = 6 * scale
    engine_y = cy + 15 * scale

    # Left engine glow
    left_engine_x = cx - 4.5 * scale
    # Glow layer
    glow_width = engine_width * 1.5
    glow_height = engine_height * 1.5
    draw.ellipse([
        left_engine_x - glow_width/2, engine_y - glow_height/2,
        left_engine_x + glow_width/2, engine_y + glow_height/2
    ], fill=(engine_color[0]//3, engine_color[1]//3, engine_color[2]//3))

    # Main engine
    draw.ellipse([
        left_engine_x - engine_width/2, engine_y - engine_height/2,
        left_engine_x + engine_width/2, engine_y + engine_height/2
    ], fill=engine_color)

    # Bright center
    draw.ellipse([
        left_engine_x - engine_width/4, engine_y - engine_height/4,
        left_engine_x + engine_width/4, engine_y + engine_height/4
    ], fill=(200, 255, 255))

    # Right engine glow
    right_engine_x = cx + 4.5 * scale
    # Glow layer
    draw.ellipse([
        right_engine_x - glow_width/2, engine_y - glow_height/2,
        right_engine_x + glow_width/2, engine_y + glow_height/2
    ], fill=(engine_color[0]//3, engine_color[1]//3, engine_color[2]//3))

    # Main engine
    draw.ellipse([
        right_engine_x - engine_width/2, engine_y - engine_height/2,
        right_engine_x + engine_width/2, engine_y + engine_height/2
    ], fill=engine_color)

    # Bright center
    draw.ellipse([
        right_engine_x - engine_width/4, engine_y - engine_height/4,
        right_engine_x + engine_width/4, engine_y + engine_height/4
    ], fill=(200, 255, 255))

    # Engine thruster particles (cyan glow trailing down)
    # Simulate the particle emitter effect
    particle_color_start = (0, 230, 255)  # Bright cyan
    particle_color_end = (102, 128, 230)  # Darker blue

    for i in range(8):
        particle_y = engine_y + (i + 1) * scale * 2.5
        particle_alpha = 1.0 - (i / 8.0)
        particle_size = (1.5 - i * 0.15) * scale

        # Color interpolation
        ratio = i / 8.0
        p_r = int(particle_color_start[0] * (1 - ratio) + particle_color_end[0] * ratio)
        p_g = int(particle_color_start[1] * (1 - ratio) + particle_color_end[1] * ratio)
        p_b = int(particle_color_start[2] * (1 - ratio) + particle_color_end[2] * ratio)
        p_color = (p_r, p_g, p_b, int(255 * particle_alpha))

        # Left thruster particles
        offset_x = random.uniform(-scale * 0.5, scale * 0.5)
        draw.ellipse([
            left_engine_x + offset_x - particle_size,
            particle_y - particle_size,
            left_engine_x + offset_x + particle_size,
            particle_y + particle_size
        ], fill=p_color)

        # Right thruster particles
        offset_x = random.uniform(-scale * 0.5, scale * 0.5)
        draw.ellipse([
            right_engine_x + offset_x - particle_size,
            particle_y - particle_size,
            right_engine_x + offset_x + particle_size,
            particle_y + particle_size
        ], fill=p_color)


def create_app_icon(size):
    """Creates app icon of given size with exact game styling"""
    # Starfield background
    img, draw = create_starfield_background(size)

    # Add nebulae (now more visible!)
    img = add_nebulae(img, size)

    # Refresh draw object after nebulae composite
    draw = ImageDraw.Draw(img)

    # Stars (varied sizes and colors like in game)
    num_stars = max(40, size // 3)  # More stars for richer field (increased)
    add_stars(draw, size, num_stars)

    # Spaceship with glow
    random.seed(100)  # Fixed seed for consistent thruster particles
    draw_spaceship(img, draw, size)

    # Convert RGBA to RGB for PNG
    if img.mode == 'RGBA':
        rgb_img = Image.new('RGB', img.size, (0, 0, 0))
        rgb_img.paste(img, mask=img.split()[3] if len(img.split()) == 4 else None)
        img = rgb_img

    return img


def generate_all_icons():
    """Generates all required icon sizes for iOS"""
    # Icon sizes for iOS (according to Contents.json)
    # Format: (base_size, scales, idiom)
    icon_specs = [
        (20, [2, 3], "iphone"),    # iPhone Notification
        (29, [2, 3], "iphone"),    # iPhone Settings
        (40, [2, 3], "iphone"),    # iPhone Spotlight
        (60, [2, 3], "iphone"),    # iPhone App
        (20, [1, 2], "ipad"),      # iPad Notification
        (29, [1, 2], "ipad"),      # iPad Settings
        (40, [1, 2], "ipad"),      # iPad Spotlight
        (76, [1, 2], "ipad"),      # iPad App
        (83.5, [2], "ipad"),       # iPad Pro
        (1024, [1], "ios-marketing")  # App Store
    ]

    output_dir = "jetshot/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(output_dir, exist_ok=True)

    images = []

    for base_size, scales, idiom in icon_specs:
        for scale in scales:
            size = int(base_size * scale)
            filename = f"icon_{base_size}x{base_size}@{scale}x.png"

            print(f"Generating {filename} ({size}x{size}px)...")

            # Set seed for consistent background stars
            random.seed(42 + int(base_size))

            icon = create_app_icon(size)
            icon.save(os.path.join(output_dir, filename), quality=95)

            # Add to JSON
            images.append({
                "filename": filename,
                "idiom": idiom,
                "scale": f"{scale}x",
                "size": f"{base_size}x{base_size}"
            })

    # Create Contents.json
    contents = {
        "images": images,
        "info": {
            "author": "xcode",
            "version": 1
        }
    }

    with open(os.path.join(output_dir, "Contents.json"), 'w') as f:
        json.dump(contents, f, indent=2)

    print(f"\n✓ All icons successfully generated in {output_dir}")
    print(f"✓ Total {len(images)} sizes")

if __name__ == "__main__":
    print("🚀 Generating Jetshot app icon...")
    print("   Using exact colors, shapes, and effects from the game")
    print()
    generate_all_icons()
    print()
    print("✨ Done! Icons are ready to use.")

