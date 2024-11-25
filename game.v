module main

import os
import sdl
import sdl.image
import sdl.ttf
import time
import math
import rand
import neuroevolution

const font_size = 16
const win_width = 500
const win_height = 512
const bg_color = sdl.Color{0x96, 0xE2, 0x82, 0xFF}
const win_title = c'Flappy Learning ported to SDL2'

struct Bird {
mut:
	x        f64  = 80
	y        f64  = 250
	width    f64  = 40
	height   f64  = 30
	alive    bool = true
	gravity  f64
	velocity f64 = 0.3
	jump     f64 = -6
}

fn (mut b Bird) flap() {
	b.gravity = b.jump
}

fn (mut b Bird) update() {
	b.gravity += b.velocity
	b.y += b.gravity
}

fn (b Bird) is_dead(height f64, pipes []Pipe) bool {
	if b.y >= height || b.y + b.height <= 0 {
		return true
	}
	for pipe in pipes {
		if !(b.x > pipe.x + pipe.width || b.x + b.width < pipe.x || b.y > pipe.y + pipe.height
			|| b.y + b.height < pipe.y) {
			return true
		}
	}
	return false
}

struct Pipe {
mut:
	x      f64 = 80
	y      f64 = 250
	width  f64 = 40
	height f64 = 30
	speed  f64 = 3
}

fn (mut p Pipe) update() {
	p.x -= p.speed
}

fn (p Pipe) is_out() bool {
	return p.x + p.width < 0
}

struct App {
mut:
	window           &sdl.Window   = sdl.null
	renderer         &sdl.Renderer = sdl.null
	background       &sdl.Texture  = sdl.null
	bird             &sdl.Texture  = sdl.null
	pipetop          &sdl.Texture  = sdl.null
	pipebottom       &sdl.Texture  = sdl.null
	font             &ttf.Font     = sdl.null
	pipes            []Pipe
	birds            []Bird
	score            int
	max_score        int
	width            f64 = win_width
	height           f64 = win_height
	spawn_interval   f64 = 90
	interval         f64
	nv               neuroevolution.Generations
	gen              []neuroevolution.Network
	alives           int
	generation       int
	background_speed f64 = 0.5
	background_x     f64
	timer_period_ms  int = 24
}

fn (mut app App) start() {
	app.interval = 0
	app.score = 0
	app.pipes = []
	app.birds = []
	app.gen = app.nv.generate()
	for _ in 0 .. app.gen.len {
		app.birds << Bird{}
	}
	app.generation++
	app.alives = app.birds.len
}

fn (app &App) is_it_end() bool {
	for i in 0 .. app.birds.len {
		if app.birds[i].alive {
			return false
		}
	}
	return true
}

fn (mut app App) update() {
	app.background_x += app.background_speed
	mut next_holl := f64(0)
	if app.birds.len > 0 {
		for i := 0; i < app.pipes.len; i += 2 {
			if app.pipes[i].x + app.pipes[i].width > app.birds[0].x {
				next_holl = app.pipes[i].height / app.height
				break
			}
		}
	}
	for j, mut bird in app.birds {
		if bird.alive {
			inputs := [
				bird.y / app.height,
				next_holl,
			]
			res := app.gen[j].compute(inputs)
			if res[0] > 0.5 {
				bird.flap()
			}
			bird.update()
			if bird.is_dead(app.height, app.pipes) {
				bird.alive = false
				app.alives--
				app.nv.network_score(app.gen[j], app.score)
				if app.is_it_end() {
					app.start()
				}
			}
		}
	}
	for k := 0; k < app.pipes.len; k++ {
		app.pipes[k].update()
		if app.pipes[k].is_out() {
			app.pipes.delete(k)
			k--
		}
	}
	if app.interval == 0 {
		delta_bord := f64(50)
		pipe_holl := f64(120)
		holl_position := math.round(rand.f64() * (app.height - delta_bord * 2.0 - pipe_holl)) +
			delta_bord
		app.pipes << Pipe{
			x:      app.width
			y:      0
			height: holl_position
		}
		app.pipes << Pipe{
			x:      app.width
			y:      holl_position + pipe_holl
			height: app.height
		}
	}
	app.interval++
	if app.interval == app.spawn_interval {
		app.interval = 0
	}
	app.score++
	app.max_score = if app.score > app.max_score { app.score } else { app.max_score }
}

fn (mut app App) run() {
	for {
		app.update()
		time.sleep(app.timer_period_ms * time.millisecond)
	}
}

fn get_image_asset_path(path string) string {
	$if android && !termux {
		return os.join_path('img', path)
	} $else {
		return os.resource_abs_path(os.join_path('assets', 'img', path))
	}
}

fn get_font_asset_path(path string) string {
	$if android && !termux {
		return os.join_path('fonts', path)
	} $else {
		return os.resource_abs_path(os.join_path('assets', 'fonts', path))
	}
}

fn emsg(msg string) IError {
	e := unsafe { cstring_to_vstring(sdl.get_error()) }
	return error('${msg}, error: ${e}')
}

fn (app &App) get_image(name string) !&sdl.Texture {
	asset_path := get_image_asset_path(name)
	rw := sdl.rw_from_file(asset_path.str, 'rb'.str)
	if rw == sdl.null {
		return emsg('Could not load image "${name}" RW from mem')
	}
	img := image.load_rw(rw, 1)
	if img == sdl.null {
		return emsg('Could not load image RW "${name}"')
	}
	return sdl.create_texture_from_surface(app.renderer, img)
}

fn (mut app App) sdl_handle_events() bool {
	evt := sdl.Event{}
	for 0 < sdl.poll_event(&evt) {
		match evt.@type {
			.quit {
				return false
			}
			.keydown {
				key := unsafe { sdl.KeyCode(evt.key.keysym.sym) }
				match key {
					.escape {
						return false
					}
					._0 {
						app.timer_period_ms = 0
					}
					.space {
						if app.timer_period_ms == 24 {
							app.timer_period_ms = 4
						} else {
							app.timer_period_ms = 24
						}
					}
					else {}
				}
			}
			else {}
		}
	}
	return true
}

fn (app &App) draw_text(x f32, y f32, text string) {
	c := sdl.Color{}
	tsurf := ttf.render_text_solid(app.font, text.str, c)
	ttext := sdl.create_texture_from_surface(app.renderer, tsurf)
	dstrect := sdl.Rect{
		x: int(x)
		y: int(y)
	}
	sdl.query_texture(ttext, sdl.null, sdl.null, &dstrect.w, &dstrect.h)
	sdl.render_copy(app.renderer, ttext, sdl.null, &dstrect)
	sdl.destroy_texture(ttext)
	sdl.free_surface(tsurf)
}

fn (app &App) draw_rect(x f32, y f32, w f32, h f32, c sdl.Color) {
	sdl.set_render_draw_color(app.renderer, c.r, c.g, c.b, c.a)
	r := sdl.Rect{
		x: int(x)
		y: int(y)
		w: int(w)
		h: int(h)
	}
	sdl.render_draw_rect(app.renderer, &r)
}

fn (app &App) draw_image(x f32, y f32, texture &sdl.Texture) {
	mut dstrect := sdl.Rect{
		x: int(x)
		y: int(y)
	}
	sdl.query_texture(texture, sdl.null, sdl.null, &dstrect.w, &dstrect.h)
	sdl.render_copy(app.renderer, texture, sdl.null, &dstrect)
}

fn (app &App) sdl_frame() {
	sdl.set_render_draw_color(app.renderer, bg_color.r, bg_color.g, bg_color.b, bg_color.a)
	sdl.render_clear(app.renderer)
	app.display()
	sdl.render_present(app.renderer)
}

fn (app &App) display() {
	mut bw, bh, ph := 0, 0, 0
	sdl.query_texture(app.background, sdl.null, sdl.null, &bw, &bh)
	sdl.query_texture(app.pipetop, sdl.null, sdl.null, sdl.null, &ph)

	for i := 0; i < int(math.ceil(app.width / bw) + 1.0); i++ {
		background_x := i * bw - math.floor(int(app.background_x) % int(bw))
		app.draw_image(f32(background_x), 0, app.background)
	}
	for i, pipe in app.pipes {
		if i % 2 == 0 {
			app.draw_image(f32(pipe.x), f32(pipe.y + pipe.height - ph), app.pipetop)
		} else {
			app.draw_image(f32(pipe.x), f32(pipe.y), app.pipebottom)
		}
	}
	for bird in app.birds {
		if bird.alive {
			app.draw_image(f32(bird.x), f32(bird.y), app.bird)
		}
	}
	app.draw_rect(0, 510, bw * 3, 5, sdl.Color{0x21, 0x19, 0x28, 255})
	app.draw_rect(0, 513, bw * 3, bh, bg_color)
	app.draw_rect(550, 0, bw + 50, bh + 20, bg_color)
	app.draw_text(10, 25, 'Score: ${app.score}')
	app.draw_text(10, 50, 'Max Score: ${app.max_score}')
	app.draw_text(10, 75, 'Generation: ${app.generation}')
	app.draw_text(10, 100, 'Alive: ${app.alives} / ${app.nv.population}')
}

fn (app &App) get_font(name string) !&ttf.Font {
	font_path := get_font_asset_path(name)
	return ttf.open_font(font_path.str, font_size)
}

fn (mut app App) sdl_setup() ! {
	// setup SDL2 and SDL2_Image
	mut compiled_version := sdl.Version{}
	C.SDL_IMAGE_VERSION(&compiled_version)
	println('Compiled against version ${compiled_version.str()}')
	linked_version := image.linked_version()
	println('Runtime loaded version ${linked_version.major}.${linked_version.minor}.${linked_version.patch}')
	$if debug ? {
		// SDL debug info, must be called before sdl.init
		sdl.log_set_all_priority(sdl.LogPriority.verbose)
	}
	sdl.init(sdl.init_video)
	ttf.init()
	app.window = sdl.create_window(win_title, sdl.windowpos_undefined, sdl.windowpos_undefined,
		win_width, win_height, 0)
	app.renderer = sdl.create_renderer(app.window, -1, u32(sdl.RendererFlags.accelerated) | u32(sdl.RendererFlags.presentvsync))
	flags := int(image.InitFlags.png)
	image_init_result := image.init(flags)
	if (image_init_result & flags) != flags {
		return emsg('Could not initialize SDL2_image')
	}
	// Hint the render, before creating textures, that we want
	// as high a scale quality as possible. This improves the
	// view quality of most textures when they are scaled down.
	sdl.set_hint(sdl.hint_render_scale_quality.str, c'2')

	// Load the used image textures:
	app.bird = app.get_image('bird.png')!
	app.pipetop = app.get_image('pipetop.png')!
	app.pipebottom = app.get_image('pipebottom.png')!
	app.background = app.get_image('background.png')!
	app.font = app.get_font('RobotoMono-Regular.ttf')!
}

fn (app &App) sdl_cleanup() {
	ttf.close_font(app.font)
	sdl.destroy_texture(app.background)
	sdl.destroy_texture(app.pipebottom)
	sdl.destroy_texture(app.pipetop)
	sdl.destroy_texture(app.bird)
	sdl.destroy_renderer(app.renderer)
	sdl.destroy_window(app.window)
	sdl.quit()
}

fn main() {
	mut app := &App{
		nv: neuroevolution.Generations{
			population: 50
			network:    [2, 2, 1]
		}
	}

	app.sdl_setup()!
	defer {
		app.sdl_cleanup()
	}

	app.start()
	spawn app.run()

	// main event/redraw loop:
	for app.sdl_handle_events() {
		app.sdl_frame()
	}
}
