# Brass Tide v0.102 — Boat and weapon detail

v0.102 — Boat and weapon detail candidate
Close-detail authored hulls now receive attached socket details and conservative exposed motor caps, and actual weapon atlas renders receive receiver/feed/collar details. Existing36 hulls, physical sockets, motor plans, neutral recoil and bounded geometry caches remain authoritative. Potentially obscured detail is omitted; distantLOD is unchanged.
Independent source review challenged cabin/hull occlusion and recoil rest. The corrected candidate uses conservative geometry blockers and existing recoil_offset(0.16)==0. Four actual CanvasItem atlas/cached/direct/oppositeheading gallery images and normal play/motion acceptance are pending. No native or art-quality pass is claimed yet.
