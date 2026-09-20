# B - Garage layout, 20 September 2026

Owner B; branch codex/b-garage-layout, base ac2bda4. Implements the annotated
Main menu -> Garage reference. Scope: garage scene/script, customize catalogue
entry, garage checks and coordination. Existing dirty A menu/audio/shared-preview
work stays separate in the original checkout.

Preview grows vertically; horizontal mouse and keyboard orbit reverse only in
Garage. Compact description contains canonical mass, battery capacity, max speed
and four individual armor plate HP values. Core HP remains. Right column is
loadout only. Catalogue entries are removed from Garage and Customize, removing
the catalogue submenus from normal navigation. Existing customization stays.
No combat, catalogue, save, protocol or hosted service change.

User follow-up: no text in the Garage viewport; invalid reasons live in the
description. Full HD (1920 x 1080) is the project display baseline and native
review resolution. The project.godot change only updates viewport dimensions;
A app/export integration should retain this baseline.

Validation (Godot 4.7.2 stable): BASELINE PASS, GARAGE CATALOGUE TEXT PASS,
GARAGE PAGINATION PASS and GARAGE TEST DRIVE GAME PASS. Native Full HD capture
reviewed at normal and 150% text, including long names and invalid builds.
The text check verifies mouse/keyboard reversal, actual 125-capacity battery,
canonical speed/plate integrity and absence of viewport text. Higher-resolution
resize checks pass. No hosted release is required or claimed for this UI change.

