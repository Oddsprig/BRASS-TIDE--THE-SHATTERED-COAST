# v0.031 focused results

| Fixture | Checks | Failures |
| --- | ---: | ---: |
| Equipment condition |90|0|
| Equipment records |89|0|
| Equipment damage |174|0|
| Paid fittings |324|0|
| Equipment UI integration |167|0|
| Campaign equipment |629|0|
| Equipment service |204|0|
| Total |1677|0|

Import/export and exported menu/campaign/battle startup also passed. Actual job:
743c0c26a91d4a0a8f9ade56d59da877. All12 individual phases exited zero and
completed cleanup; selected work plus charged setup81.464s. Source input was
c8cfa9e1a87fe04cd335a89ce983d4a5e49d11fc. Root's independent verdict is in
QA FOCUSED v0.031.json. The job itself remains failed at its final raw-byte guard:
only23 `.import` files changed CRLF/LF formatting; all code, tests, data and raw
assets were byte-identical. Original failed records are preserved.

The earlier637-check campaign/publication pass remains separate. Full-game
regression, dense-fleet performance and rendered/audio/human play remain deferred.
Final documentation export/startup receipt is included in the portable tests/.
