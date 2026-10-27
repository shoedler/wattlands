extends RefCounted
# Hand-tuned shapes in reference (1088x608) coordinates.

const TANK_OUTER := [
	Vector2(95, 389), Vector2(58, 362), Vector2(32, 318), Vector2(35, 294), Vector2(41, 279),
	Vector2(127, 261), Vector2(127, 246), Vector2(190, 246), Vector2(193, 217), Vector2(227, 217),
	Vector2(228, 127), Vector2(238, 127), Vector2(239, 209), Vector2(279, 209), Vector2(279, 194),
	Vector2(303, 194), Vector2(303, 208), Vector2(399, 208), Vector2(415, 227), Vector2(418, 239),
	Vector2(466, 241), Vector2(468, 244.5), Vector2(529, 245), Vector2(530, 256), Vector2(468, 256),
	Vector2(420, 254), Vector2(415, 258), Vector2(440, 258), Vector2(467, 260), Vector2(468, 272),
	Vector2(497, 275), Vector2(499, 283), Vector2(475, 284), Vector2(500, 287), Vector2(513, 290),
	Vector2(535, 291), Vector2(536, 299), Vector2(532, 313), Vector2(541, 317), Vector2(541, 335),
	Vector2(536, 337), Vector2(536, 362), Vector2(522, 381), Vector2(512, 389),
]# Crew + searchlight on the turret top (not part of the tank art).
const TURRET_CREW := Rect2i(270, 180, 105, 36)

const SEARCH_BEAM := [
	Vector2(356, 188), Vector2(430, 196), Vector2(530, 214), Vector2(620, 232), Vector2(632, 292),
	Vector2(560, 298), Vector2(470, 262), Vector2(400, 232), Vector2(358, 216),
]
const HEAD_BEAM := [
	Vector2(530, 312), Vector2(600, 318), Vector2(710, 338), Vector2(728, 395), Vector2(540, 395),
]
const SMOKE := [
	Vector2(15, 172), Vector2(140, 172), Vector2(150, 250), Vector2(110, 300), Vector2(75, 395),
	Vector2(0, 395), Vector2(0, 200),
]

const INNER := [
	[
		Vector2(100, 381), Vector2(42, 333), Vector2(38, 318), Vector2(39, 300), Vector2(44, 284), Vector2(130, 272),
		Vector2(186, 268), Vector2(196, 263), Vector2(412, 263), Vector2(420, 274), Vector2(506, 306), Vector2(529, 316), Vector2(532, 342), Vector2(527, 362),
		Vector2(515, 376), Vector2(505, 381),
	],
	[
		Vector2(200, 226), Vector2(246, 226), Vector2(246, 216), Vector2(398, 216), Vector2(410, 232),
		Vector2(412, 262), Vector2(200, 262),
	],
	[Vector2(132, 254), Vector2(186, 254), Vector2(186, 274), Vector2(132, 274)],
	[
		Vector2(404, 241), Vector2(420, 241.5), Vector2(466, 243), Vector2(468, 246.5), Vector2(527, 247),
		Vector2(527.5, 253.5), Vector2(468, 253.5), Vector2(420, 251), Vector2(410, 256), Vector2(404, 256),
	],
	[
		Vector2(400, 262), Vector2(440, 261), Vector2(465, 263), Vector2(466, 274), Vector2(472, 277),
		Vector2(494, 278), Vector2(496, 280), Vector2(494, 281), Vector2(472, 281), Vector2(472, 285),
		Vector2(498, 290), Vector2(512, 293), Vector2(531, 294), Vector2(532, 297), Vector2(512, 297),
		Vector2(500, 303), Vector2(529, 317), Vector2(539, 319), Vector2(539, 332), Vector2(533, 334),
		Vector2(531, 345), Vector2(526, 362), Vector2(515, 376), Vector2(400, 376),
	],
]
# Where the background is beam-lit: alpha comes from INNER only.
const NO_DIFF := [
	[Vector2(356, 186), Vector2(560, 210), Vector2(560, 300), Vector2(470, 300), Vector2(400, 262), Vector2(360, 216)],
	[Vector2(536, 300), Vector2(560, 300), Vector2(560, 400), Vector2(536, 400)],
]
# Thin parts where the diff edge may reach beyond INNER (antenna, periscope, green light).
const DIFF_EXTRA := [Rect2i(229, 126, 9, 98), Rect2i(145, 243, 12, 12)]
