extends CharacterBody2D

const ROLE_COLORS := {
	"Hacker": Color(0.20, 0.68, 1.0),
	"Engineer": Color(0.27, 0.92, 0.55),
	"Scout": Color(1.0, 0.78, 0.18),
	"Guardian": Color(1.0, 0.30, 0.28),
}

var peer_id: int = 1
var role: String = "Hacker"
var health: int = 3
var down: bool = false
var down_timer: float = 0.0
var ability_cooldown: float = 0.0
var shield_time: float = 0.0
var in_exit: bool = false
var connected: bool = true
var input_vector: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var spawn_position: Vector2 = Vector2.ZERO
var pulse: float = 0.0
var nickname: String = ""

func _ready() -> void:
	add_to_group("quadra_players")
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var collider := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	collider.shape = circle
	add_child(collider)
	queue_redraw()

func _process(delta: float) -> void:
	pulse += delta * 3.0
	if not multiplayer.is_server() and not is_multiplayer_authority() and global_position.distance_to(target_position) > 1.0:
		global_position = global_position.lerp(target_position, min(delta * 12.0, 1.0))
	queue_redraw()

func _draw() -> void:
	var color: Color = ROLE_COLORS.get(role, Color.WHITE)
	var halo := 1.0 + sin(pulse) * 0.045
	if down:
		color = Color(0.46, 0.52, 0.58)
	draw_circle(Vector2(0, 7), 22.0 * halo, Color(0.0, 0.0, 0.0, 0.42))
	if shield_time > 0.0:
		draw_arc(Vector2.ZERO, 33.0, 0.0, TAU, 48, Color(1.0, 0.42, 0.33, 0.8), 3.0, true)
	draw_circle(Vector2.ZERO, 25.0 * halo, Color(color.r, color.g, color.b, 0.11))
	draw_circle(Vector2.ZERO, 17.0, color.darkened(0.45))
	draw_circle(Vector2.ZERO, 13.0, color)
	draw_circle(Vector2(-4, -4), 4.0, Color(0.9, 0.98, 1.0, 0.82))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -23), Vector2(6, -14), Vector2(-6, -14)]), Color(0.9, 0.98, 1.0, 0.92))
	match role:
		"Hacker":
			draw_line(Vector2(-8, 5), Vector2(8, 5), Color(0.04, 0.16, 0.25), 2.0)
			draw_circle(Vector2(-8, 5), 2.0, Color(0.79, 0.96, 1.0))
			draw_circle(Vector2(8, 5), 2.0, Color(0.79, 0.96, 1.0))
		"Engineer":
			draw_colored_polygon(PackedVector2Array([Vector2(1, -8), Vector2(-5, 1), Vector2(-1, 1), Vector2(-3, 8), Vector2(5, -2), Vector2(1, -2)]), Color(0.06, 0.23, 0.13))
		"Scout":
			draw_arc(Vector2.ZERO, 8.0, -0.7, 0.7, 16, Color(0.30, 0.25, 0.03), 2.0, true)
			draw_arc(Vector2.ZERO, 8.0, 2.4, 3.8, 16, Color(0.30, 0.25, 0.03), 2.0, true)
		"Guardian":
			draw_colored_polygon(PackedVector2Array([Vector2(0, -9), Vector2(7, -5), Vector2(5, 4), Vector2(0, 9), Vector2(-5, 4), Vector2(-7, -5)]), Color(0.28, 0.05, 0.06))
	if not connected:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 36, Color(0.58, 0.67, 0.75, 0.8), 2.0, true)
	var font := ThemeDB.fallback_font
	if font != null:
		var label := nickname if nickname != "" else "%02d" % peer_id
		draw_string(font, Vector2(-36, 43), label, HORIZONTAL_ALIGNMENT_CENTER, 72.0, 12, Color(0.80, 0.89, 0.95))
		if down:
			draw_string(font, Vector2(-36, 58), "DOWN", HORIZONTAL_ALIGNMENT_CENTER, 72.0, 10, Color(1.0, 0.45, 0.38))
