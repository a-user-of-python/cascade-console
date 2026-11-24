// dump_view_fixture — feeds the Swift viewer harness (v0.2.3).
//
// Runs two commands through the real Layer-2 session and writes the
// cc_view_data result, field for field, to a binary fixture the
// Swift harness (Shared/Viewer/Verification/swift-harness/main.swift)
// consumes: it rebuilds EngineViewObjects from the fixture, runs the
// PRODUCTION EngineMeshAdapter + MeshBufferLoader on them, and
// asserts the geometry survives — including a byte-level re-read of
// the [MeshVertex] buffer with the renderer's vertex-descriptor
// layout, the exact read that produced the v0.2.2 on-device fan.
//
// Why this exists: until v0.2.3 no gate ever executed the Swift
// parsing/layout code — the C++ view data was proven good while the
// Swift side misdescribed it to the GPU. This fixture is generated
// in CI by whichever backend the job links (the mc-backend-matrix
// job links the device-path mc backend), so the Swift code is
// tested against the real device-path bytes.
//
// Fixture format "CCFX" (all little-endian):
//   char[4] "CCFX", int32 version (=2), int32 objectCount
//   per object: int32 nameByteCount, name bytes,
//               int32 vertexCount, int32 triangleCount,
//               float32 vertices[3*vertexCount],
//               int32  indices[3*triangleCount],
//               float64 volume, float64 bbox[6],
//               int32 faceRangeCount,
//               faceRange[int32 faceIndex, int32 indexStart,
//                         int32 indexCount] * faceRangeCount,
//               int32 edgeCount,                       (v2, v0.2.4)
//               edge[int32 edgeIndex, float64 start[3],
//                    float64 end[3]] * edgeCount
//
// Usage: dump_view_fixture <output.ccfx>
#include "cc_facade.h"
#include <cstdio>
#include <cstring>

static void wi32(FILE* f, int v) { fwrite(&v, 4, 1, f); }
static void wf64(FILE* f, double v) { fwrite(&v, 8, 1, f); }

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: dump_view_fixture <output.ccfx>\n"); return 2; }
    CCSession* s = cc_session_create();
    if (!s) { fprintf(stderr, "session create failed\n"); return 1; }
    char* out = nullptr;
    // A box with distinct extents (the user's failing case was
    // `box test 10 2 10`) and a cylinder for a curved tessellation.
    const char* cmds[] = { "box test 10 2 10", "cylinder cyl 3 12" };
    for (const char* cmd : cmds) {
        int rc = cc_execute(s, cmd, &out);
        if (rc != 0) {
            fprintf(stderr, "'%s' failed rc=%d: %s\n", cmd, rc, cc_last_error_message(s));
            return 1;
        }
        cc_free_string(out); out = nullptr;
    }
    CCViewData* objs = nullptr; int count = 0;
    int rc = cc_view_data(s, nullptr, 0.5, &objs, &count);
    if (rc != 0) {
        fprintf(stderr, "cc_view_data failed rc=%d: %s\n", rc, cc_last_error_message(s));
        return 1;
    }
    FILE* f = fopen(argv[1], "wb");
    if (!f) { perror("fopen"); return 1; }
    fwrite("CCFX", 1, 4, f);
    wi32(f, 2); wi32(f, count);
    for (int i = 0; i < count; i++) {
        CCViewData& d = objs[i];
        int nl = (int)strlen(d.name);
        wi32(f, nl); fwrite(d.name, 1, nl, f);
        wi32(f, d.vertexCount); wi32(f, d.triangleCount);
        fwrite(d.vertices, 4, (size_t)3 * d.vertexCount, f);
        fwrite(d.indices, 4, (size_t)3 * d.triangleCount, f);
        wf64(f, d.volume);
        for (int k = 0; k < 6; k++) wf64(f, d.bbox[k]);
        wi32(f, d.faceRangeCount);
        for (int j = 0; j < d.faceRangeCount; j++) {
            wi32(f, d.faceRanges[j].faceIndex);
            wi32(f, d.faceRanges[j].indexStart);
            wi32(f, d.faceRanges[j].indexCount);
        }
        wi32(f, d.edgeCount);
        for (int j = 0; j < d.edgeCount; j++) {
            wi32(f, d.edges[j].edgeIndex);
            for (int k = 0; k < 3; k++) wf64(f, d.edges[j].start[k]);
            for (int k = 0; k < 3; k++) wf64(f, d.edges[j].end[k]);
        }
        printf("fixture object '%s': %d vertices, %d triangles, volume %.4f, %d edges\n",
               d.name, d.vertexCount, d.triangleCount, d.volume, d.edgeCount);
    }
    fclose(f);
    cc_free_view_data(objs, count);
    cc_session_destroy(s);
    return 0;
}
