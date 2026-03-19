using Gtk;
using GLib;

namespace Dino.Ui {

public class EffectsOverlay : DrawingArea {

    private struct Particle {
        public double x;
        public double y;
        public double vx;
        public double vy;
        public double size;
        public double r;
        public double g;
        public double b;
        public double rotation;
        public double rot_speed;
    }

    private Particle[] particles;
    private int particle_count = 0;
    private uint tick_id = 0;
    private int64 start_time = 0;
    private int64 duration_us = 0;
    private string current_effect = "";

    construct {
        set_draw_func(on_draw);
        this.visible = false;
        this.can_target = false;
        this.hexpand = true;
        this.vexpand = true;
    }

    public void trigger_party() {
        current_effect = "party";
        int w = get_width();
        int h = get_height();
        if (w <= 0) w = 600;
        if (h <= 0) h = 400;

        particle_count = 200;
        particles = new Particle[particle_count];
        var rand = new GLib.Rand();

        for (int i = 0; i < particle_count; i++) {
            particles[i] = Particle() {
                x = rand.double_range(0, w),
                y = -rand.double_range(10, h * 0.5),
                vx = rand.double_range(-3, 3),
                vy = rand.double_range(2, 7),
                size = rand.double_range(4, 12),
                r = rand.double_range(0.1, 1),
                g = rand.double_range(0.1, 1),
                b = rand.double_range(0.1, 1),
                rotation = rand.double_range(0, Math.PI * 2),
                rot_speed = rand.double_range(-0.15, 0.15)
            };
        }

        start_animation(4000000);
    }

    public void trigger_space() {
        current_effect = "space";
        int w = get_width();
        int h = get_height();
        if (w <= 0) w = 600;
        if (h <= 0) h = 400;

        particle_count = 10;
        particles = new Particle[particle_count];
        var rand = new GLib.Rand();

        for (int i = 0; i < particle_count; i++) {
            particles[i] = Particle() {
                x = rand.double_range(w * 0.1, w * 0.9),
                y = h + rand.double_range(20, 80),
                vx = rand.double_range(-0.5, 0.5),
                vy = rand.double_range(-5, -9),
                size = rand.double_range(18, 35),
                r = rand.double_range(0.6, 1),
                g = rand.double_range(0.6, 1),
                b = rand.double_range(0.6, 1),
                rotation = 0,
                rot_speed = 0
            };
        }

        start_animation(3500000);
    }

    public void trigger_attention() {
        current_effect = "attention";
        particle_count = 0;
        particles = new Particle[0];

        var root = this.get_root();
        if (root != null && root is Gtk.Window) {
            ((Gtk.Window) root).present();
        }

        start_animation(2000000);
    }

    private void start_animation(int64 dur_us) {
        if (tick_id != 0) {
            remove_tick_callback(tick_id);
            tick_id = 0;
        }

        this.visible = true;
        start_time = GLib.get_monotonic_time();
        duration_us = dur_us;

        tick_id = add_tick_callback(() => {
            int64 elapsed = GLib.get_monotonic_time() - start_time;

            if (elapsed > duration_us) {
                this.visible = false;
                particle_count = 0;
                tick_id = 0;
                queue_draw();
                return false;
            }

            update_particles();
            queue_draw();
            return true;
        });
    }

    private void update_particles() {
        if (current_effect == "party") {
            for (int i = 0; i < particle_count; i++) {
                particles[i].x += particles[i].vx;
                particles[i].y += particles[i].vy;
                particles[i].vy += 0.12;
                particles[i].vx *= 0.995;
                particles[i].rotation += particles[i].rot_speed;
            }
        } else if (current_effect == "space") {
            for (int i = 0; i < particle_count; i++) {
                particles[i].x += particles[i].vx;
                particles[i].y += particles[i].vy;
                particles[i].vy -= 0.08;
            }
        }
    }

    private void on_draw(DrawingArea area, Cairo.Context cr, int w, int h) {
        if (!this.visible) return;

        if (current_effect == "party") {
            draw_confetti(cr, w, h);
        } else if (current_effect == "space") {
            draw_rockets(cr, w, h);
        } else if (current_effect == "attention") {
            draw_attention(cr, w, h);
        }
    }

    private void draw_confetti(Cairo.Context cr, int w, int h) {
        for (int i = 0; i < particle_count; i++) {
            Particle p = particles[i];
            if (p.y > h + 20) continue;

            cr.save();
            cr.translate(p.x, p.y);
            cr.rotate(p.rotation);
            cr.set_source_rgba(p.r, p.g, p.b, 0.9);

            // Alternate between rectangles and circles for variety
            if (i % 3 == 0) {
                cr.rectangle(-p.size / 2, -p.size / 4, p.size, p.size / 2);
            } else if (i % 3 == 1) {
                cr.arc(0, 0, p.size / 3, 0, Math.PI * 2);
            } else {
                cr.move_to(0, -p.size / 2);
                cr.line_to(-p.size / 3, p.size / 3);
                cr.line_to(p.size / 3, p.size / 3);
                cr.close_path();
            }
            cr.fill();
            cr.restore();
        }
    }

    private void draw_rockets(Cairo.Context cr, int w, int h) {
        int64 elapsed = GLib.get_monotonic_time() - start_time;

        for (int i = 0; i < particle_count; i++) {
            Particle p = particles[i];
            if (p.y < -100) continue;
            double s = p.size;

            cr.save();
            cr.translate(p.x, p.y);

            // Rocket nose cone
            cr.set_source_rgba(p.r, p.g, p.b, 1.0);
            cr.move_to(0, -s * 1.2);
            cr.line_to(-s * 0.3, -s * 0.4);
            cr.line_to(s * 0.3, -s * 0.4);
            cr.close_path();
            cr.fill();

            // Rocket body
            cr.set_source_rgba(p.r * 0.8, p.g * 0.8, p.b * 0.8, 1.0);
            cr.rectangle(-s * 0.3, -s * 0.4, s * 0.6, s * 0.8);
            cr.fill();

            // Fins
            cr.set_source_rgba(0.8, 0.2, 0.1, 1.0);
            cr.move_to(-s * 0.3, s * 0.2);
            cr.line_to(-s * 0.55, s * 0.5);
            cr.line_to(-s * 0.3, s * 0.4);
            cr.close_path();
            cr.fill();
            cr.move_to(s * 0.3, s * 0.2);
            cr.line_to(s * 0.55, s * 0.5);
            cr.line_to(s * 0.3, s * 0.4);
            cr.close_path();
            cr.fill();

            // Window
            cr.set_source_rgba(0.5, 0.8, 1.0, 1.0);
            cr.arc(0, -s * 0.1, s * 0.12, 0, Math.PI * 2);
            cr.fill();

            // Flame - flickering
            double flicker = Math.sin((double) elapsed / 40000.0 + i * 1.5) * 0.4 + 0.7;
            double flame_h = s * 0.6 * flicker;

            // Outer flame (orange)
            cr.set_source_rgba(1.0, 0.5, 0.0, 0.9 * flicker);
            cr.move_to(-s * 0.25, s * 0.4);
            cr.line_to(0, s * 0.4 + flame_h);
            cr.line_to(s * 0.25, s * 0.4);
            cr.close_path();
            cr.fill();

            // Inner flame (yellow)
            cr.set_source_rgba(1.0, 1.0, 0.2, 0.9 * flicker);
            cr.move_to(-s * 0.12, s * 0.4);
            cr.line_to(0, s * 0.4 + flame_h * 0.6);
            cr.line_to(s * 0.12, s * 0.4);
            cr.close_path();
            cr.fill();

            // Smoke trail
            double smoke_alpha = 0.15;
            for (int j = 1; j <= 5; j++) {
                double sy = s * 0.4 + flame_h + j * s * 0.25;
                double sr = s * 0.1 + j * s * 0.08;
                cr.set_source_rgba(0.7, 0.7, 0.7, smoke_alpha);
                cr.arc(Math.sin((double) elapsed / 80000.0 + j) * 3, sy, sr, 0, Math.PI * 2);
                cr.fill();
                smoke_alpha *= 0.6;
            }

            cr.restore();
        }
    }

    private void draw_attention(Cairo.Context cr, int w, int h) {
        int64 elapsed = GLib.get_monotonic_time() - start_time;
        double t = (double) elapsed / (double) duration_us;
        if (t > 1.0) t = 1.0;

        double fade = 1.0 - t;

        // Pulsing border
        double pulse = Math.sin(t * Math.PI * 10);
        double border_alpha = (0.4 + pulse * 0.3) * fade;
        if (border_alpha < 0) border_alpha = 0;
        double border_width = 5 + Math.sin(t * Math.PI * 8) * 3;

        cr.set_source_rgba(1.0, 0.15, 0.15, border_alpha);
        cr.set_line_width(border_width);
        double offset = border_width / 2;
        cr.rectangle(offset, offset, w - border_width, h - border_width);
        cr.stroke();

        // Central flash
        double flash_alpha = Math.sin(t * Math.PI * 6) * 0.12 * fade;
        if (flash_alpha > 0) {
            cr.set_source_rgba(1.0, 0.3, 0.1, flash_alpha);
            cr.rectangle(0, 0, w, h);
            cr.fill();
        }

        // Exclamation icon in center
        double icon_scale = Math.sin(t * Math.PI * 5) * 0.15 + 1.0;
        double icon_alpha = (0.6 + Math.sin(t * Math.PI * 8) * 0.4) * fade;
        if (icon_alpha < 0) icon_alpha = 0;

        cr.save();
        cr.translate(w / 2.0, h / 2.0);
        cr.scale(icon_scale, icon_scale);

        // Circle background
        cr.set_source_rgba(1.0, 0.2, 0.1, icon_alpha * 0.3);
        cr.arc(0, 0, 40, 0, Math.PI * 2);
        cr.fill();

        // Exclamation bar
        cr.set_source_rgba(1.0, 0.25, 0.15, icon_alpha);
        cr.set_line_width(6);
        cr.set_line_cap(Cairo.LineCap.ROUND);
        cr.move_to(0, -20);
        cr.line_to(0, 8);
        cr.stroke();

        // Exclamation dot
        cr.arc(0, 20, 4, 0, Math.PI * 2);
        cr.fill();

        cr.restore();
    }
}

}
