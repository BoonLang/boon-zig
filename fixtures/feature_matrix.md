# Feature Matrix

- Source commit: `c924d9f7d7e1c156604c9377e0487db48c278353`
- Parser status reflects the current `boon-zig parse` pass over imported `.bn` files.
- `P0` marks the upstream hard-gate examples from `PLAN.md`.

| Example | Category | P0 | Parser | Persist | persist cases | bn | expected | refs/docs | HOLD | LATEST | WHEN | WHILE | THEN | LINK | LIST | TEXT | FLUSH | PULSES |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| button_hover_test | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | no | no | no | yes | no | yes | yes | yes | no | no |
| button_hover_to_click_test | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | no | yes | yes | yes | yes | yes | no | no |
| cells | playground | yes | DONE | NOT_STARTED | 0 | 1 | 1 | 1 | yes | no | yes | yes | yes | yes | yes | yes | no | no |
| cells_dynamic | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | yes | yes | yes | yes | yes | yes | no | no |
| chained_list_remove_bug | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | yes | yes | yes | yes | yes | yes | no | no |
| checkbox_test | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | yes | no | yes | yes | yes | yes | no | no |
| circle_drawer | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 1 | no | no | yes | no | no | yes | yes | yes | no | no |
| complex_counter | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 2 | yes | yes | yes | no | yes | yes | yes | yes | no | no |
| counter | playground | yes | DONE | DONE | 3 | 1 | 1 | 4 | no | yes | no | no | yes | yes | yes | yes | no | no |
| counter_hold | playground | no | DONE | DONE | 1 | 1 | 1 | 0 | yes | no | no | no | yes | yes | yes | yes | no | no |
| crud | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 1 | yes | yes | yes | yes | yes | yes | yes | yes | no | no |
| fibonacci | playground | no | DONE | NOT_STARTED | 1 | 1 | 1 | 0 | yes | no | no | yes | yes | no | no | yes | no | no |
| filter_checkbox_bug | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | yes | yes | yes | yes | yes | yes | yes | no | no |
| flight_booker | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 1 | yes | no | yes | yes | yes | yes | yes | yes | no | no |
| hello_world | playground | no | DONE | NOT_STARTED | 1 | 1 | 1 | 0 | no | no | no | no | no | no | no | yes | no | no |
| hw_examples | hardware | no | DONE | NOT_STARTED | 0 | 15 | 0 | 8 | yes | no | yes | yes | yes | no | yes | no | no | no |
| interval | playground | yes | DONE | PARTIAL | 1 | 1 | 1 | 2 | no | no | no | no | yes | no | no | no | no | no |
| interval_hold | playground | no | DONE | PARTIAL | 1 | 1 | 1 | 0 | yes | no | no | no | yes | no | no | no | no | no |
| latest | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | no | yes | no | no | yes | yes | yes | yes | no | no |
| layers | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | no | no | no | no | no | no | yes | yes | no | no |
| list_map_block | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | no | no | yes | yes | no | no | yes | yes | no | no |
| list_map_external_dep | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | no | yes | yes | yes | yes | yes | no | no |
| list_object_state | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | no | no | yes | yes | yes | yes | no | no |
| list_retain_count | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | no | yes | yes | no | no | yes | yes | yes | no | no |
| list_retain_reactive | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | yes | no | yes | yes | yes | yes | no | no |
| list_retain_remove | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | no | yes | yes | no | yes | yes | yes | yes | no | no |
| minimal | playground | no | DONE | NOT_STARTED | 1 | 1 | 1 | 0 | no | no | no | no | no | no | no | no | no | no |
| pages | playground | no | DONE | NOT_STARTED | 2 | 1 | 1 | 0 | no | yes | yes | yes | yes | yes | yes | yes | no | no |
| shopping_list | playground | no | DONE | NOT_STARTED | 2 | 1 | 1 | 0 | no | yes | yes | no | yes | yes | yes | yes | no | no |
| switch_hold_test | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | no | yes | yes | yes | yes | yes | no | no |
| temperature_converter | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 1 | yes | yes | no | yes | yes | yes | yes | yes | no | no |
| text_interpolation_update | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | no | yes | yes | yes | yes | yes | no | no |
| then | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | no | no | yes | yes | yes | yes | no | no |
| timer | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 1 | yes | yes | no | no | yes | yes | yes | yes | no | no |
| todo_mvc | playground | yes | DONE | NOT_STARTED | 2 | 1 | 1 | 2 | yes | yes | yes | yes | yes | yes | yes | yes | no | no |
| todo_mvc_physical | physical | yes | DONE | NOT_STARTED | 0 | 8 | 1 | 18 | yes | yes | yes | yes | yes | yes | yes | yes | yes | no |
| when | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | yes | yes | no | yes | yes | yes | yes | no | no |
| while | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | no | yes | no | yes | yes | yes | yes | yes | no | no |
| while_function_call | playground | no | DONE | NOT_STARTED | 0 | 1 | 1 | 0 | yes | no | no | yes | yes | yes | yes | yes | no | no |
