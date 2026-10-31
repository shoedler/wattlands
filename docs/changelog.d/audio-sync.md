# Changelog: audio-sync

- The engine sound now keeps time with your cadence evenly at every rpm. Godot's frame timing used to push each stroke up to a sixtieth of a second early or late, in a slow repeating wave; strokes now run on real time and stay within one frame of the crank on screen, for as long as you ride.
