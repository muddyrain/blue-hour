# Building source process

Tool: OpenAI built-in image_gen, transparent_background=true, eight independent calls, 2026-11-04. No paid API fallback or third-party image input. PNG originals here are editable raster sources. Runtime normalization is reproducible with tools/prepare_world_art.py; manifest binds every source and output SHA.

Prompt brief (summary, not a verbatim transcript): original hand-painted anime blue-hour survival building sprites, high orthographic three-quarter camera, horizontal facade with roof visible; no isometric diamond or vanishing perspective. Complete single building, alpha margin, blue-grey/teal shadows, restrained warm amber light and weathering; no terrain, characters, logos or text, no cast shadow.

- Convenience store: compact one-storey shop, teal corrugated roof, narrow blue/cream awning, central glass door, drink crates.
- Supermarket: wide flat mint-grey roof with two fans, green/cream awning, central sliding doors, loading shutter.
- Eatery: narrow timber/cream restaurant, charcoal tiled gable, terracotta awning, lantern, exhaust and stools.
- Warehouse: broad corrugated roof, central roller shutter, side personnel door, pallets, small warm lamp.
- Garage: squat asymmetric roof, half-open garage bay, visible workbench, side office, tools and tires.
- Detached home: compact two-storey cream house, slate gable, porch, residential windows and planter.
- Row house: three connected narrow two-storey homes, continuous roof, three entrances and repetitive window rhythm.
- Small apartment: compact three-storey block, flat roof, visible balconies/galleries, exterior stair and central entrance.

Technical edits only: alpha bounding box above16, proportional LANCZOS fit448x576, canvas512x640, ground pivot256/608. Roof/front partition512 is rendered in Godot; no scripted repainting or AI grid slicing. Door anchors were individually inspected against the normalized sprites before final acceptance.
