class_name WorkoutImport
extends ZwoImport
## Deprecated alias, kept only for one caller outside this game (W4, QT-6). The platform's .zwo
## importer is ZwoImport (addons/wattlands/sim/workout_import.gd): platform classes never carry
## a game prefix (BRIEF 6), and the Workout game owns the Workout prefix, so the alias lives
## here. tests/scenarios/workout/test_zwo_import.gd (qa's) still names WorkoutImport; once it
## uses ZwoImport this file goes. New code uses ZwoImport (its static functions are inherited:
## WorkoutImport.parse_zwo_file(path) == ZwoImport.parse_zwo_file(path)).
