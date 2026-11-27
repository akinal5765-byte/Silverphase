# Local-only experimental materials

[简体中文](LOCAL-MATERIALS.zh-CN.md) · **English**

A normal build in a maintainer checkout stages materials from the ignored
`private-fixtures/local-experimental-materials/` archive. The archived catalog
selects twelve private films; superseded Tri-X/HP5/paper aliases continue to use
the adopted product materials. Profiles, filter entries and covers are copied
only into generated engine resources and `LocalMaterials/`. The public catalog
and base/product data stay unchanged. Both macOS and iOS builds use this path.

The Experimental category includes the public Fotufilm collection adapted by
Negs and, in maintainer builds with the overlay enabled, the private films.
The staging switch controls the private overlay only.

For public source-only checkouts without the archive, ordinary builds include
the tracked catalog. For distribution from a maintainer checkout,
explicitly disable the overlay during both resource preparation and Xcode build:

```sh
export SILVERPHASE_LOCAL_MATERIALS=0
engine/build.sh bundle
# Run the platform's normal xcodebuild command in this same environment.
```

The staging tool removes previously staged local profiles/catalog/covers when
disabled, including reuse of the same build directory. Clear the environment
variable (or set it to `1`) for subsequent personal builds. Never force-add
private materials, generated `LocalMaterials/`, private photos or personal edits.
A release source archive does not include the ignored local material archive.
