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
// Usage: dump_view_fixture <output.ccfx> [output_ns.txt]
//
// With a second argument it also writes the v0.3.0 NAMESPACE fixture:
// a scripted UI-step scenario (the step table below) executed against
// the real backend, with each step's engine-verified assigned
// qualified name and volume, plus a fresh-session replay of the same
// lines. The Swift harness rebuilds the same steps through the
// PRODUCTION ReplayBuilder and asserts its lines, auto-names and
// directory grouping match this fixture byte for byte — the model
// layer's naming/replay logic is thereby proven against the real
// engine, not against a Swift-side guess.
#include "cc_facade.h"
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

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

    if (argc < 3) return 0;

    // ---- namespace scenario fixture (v0.3.0) -------------------------
    // Each row: the UI step (command, name field, params as the Swift
    // step store holds them), the command line the production
    // ReplayBuilder must produce for it, the qualified name the engine
    // must assign, and the analytic volume (-1 = record the measured
    // volume, -2 = profile step, no volume).
    struct NSStep {
        const char* command; const char* name; const char* params;
        const char* line; const char* assigned; double volume;
    };
    static const NSStep kSteps[] = {
        {"box", "part", "width=10;depth=10;height=10;atX=0;atY=0;atZ=0",
         "box part 10 10 10", "box:part", 1000.0},
        {"box", "part", "width=10;depth=10;height=10;atX=0;atY=0;atZ=0",
         "box part2 10 10 10", "box:part2", 1000.0},
        {"cylinder", "", "radius=5;height=10;atX=0;atY=0;atZ=0",
         "cylinder cylinder1 5 10", "cylinder:cylinder1", 785.3981633974483},
        {"cut", "part", "a=box:part;b=cylinder:cylinder1",
         "cut part box:part cylinder:cylinder1", "cut:part", 803.6504591586153},
        {"fillet", "", "source=box:part2;radius=1;edges=",
         "fillet fillet1 box:part2 1", "fillet:fillet1", -1.0},
        {"translate", "moved", "source=box:part2;dx=20;dy=0;dz=0",
         "translate moved box:part2 20 0 0", "translate:moved", 1000.0},
        {"profile", "prof", "points=0,0 10,0 10,10 0,10",
         "profile prof 0,0 10,0 10,10 0,10", "profile:prof", -2.0},
        {"extrude", "plate", "profile=profile:prof;distance=5",
         "extrude plate profile:prof 5", "extrude:plate", 500.0},
        {"box", "part2", "width=10;depth=10;height=10;atX=0;atY=0;atZ=0",
         "box part3 10 10 10", "box:part3", 1000.0},
        {"box", "", "width=1;depth=1;height=1;atX=0;atY=0;atZ=0",
         "box box1 1 1 1", "box:box1", 1.0},
    };
    const int kStepCount = (int)(sizeof(kSteps) / sizeof(kSteps[0]));

    auto runScenario = [&](CCSession* sess, std::vector<double>& measured) -> bool {
        char* o = nullptr;
        for (int k = 0; k < kStepCount; ++k) {
            int rc = cc_execute(sess, kSteps[k].line, &o);
            cc_free_string(o); o = nullptr;
            if (rc != 0) {
                fprintf(stderr, "ns fixture: line '%s' failed rc=%d: %s\n",
                        kSteps[k].line, rc, cc_last_error_message(sess));
                return false;
            }
            if (kSteps[k].volume == -2.0) { measured.push_back(-2.0); continue; }
            double v = 0, a = 0, bb[6]; int fc = 0, ec = 0;
            if (cc_object_stats(sess, kSteps[k].assigned, &v, &a, bb, &fc, &ec) != 0) {
                fprintf(stderr, "ns fixture: assigned name '%s' not in session\n",
                        kSteps[k].assigned);
                return false;
            }
            if (kSteps[k].volume >= 0 && std::fabs(v - kSteps[k].volume) > 0.01) {
                fprintf(stderr, "ns fixture: '%s' volume %.6f != analytic %.6f\n",
                        kSteps[k].assigned, v, kSteps[k].volume);
                return false;
            }
            measured.push_back(v);
        }
        return true;
    };

    CCSession* s1 = cc_session_create();
    std::vector<double> measured;
    if (!s1 || !runScenario(s1, measured)) return 1;
    // Object keys only (the profile lives in the profiles map).
    std::vector<std::string> names;
    for (int k = 0; k < cc_object_count(s1); ++k) names.push_back(cc_object_name(s1, k));
    if ((int)names.size() != kStepCount - 1) {
        fprintf(stderr, "ns fixture: expected %d objects, got %d\n",
                kStepCount - 1, (int)names.size());
        return 1;
    }
    // Replay into a fresh session: same lines, same names + volumes.
    CCSession* s2 = cc_session_create();
    std::vector<double> measured2;
    if (!s2 || !runScenario(s2, measured2)) return 1;
    bool replaySame = measured.size() == measured2.size();
    for (size_t k = 0; replaySame && k < measured.size(); ++k)
        if (std::fabs(measured[k] - measured2[k]) > 1e-6) replaySame = false;
    if (cc_object_count(s2) != cc_object_count(s1)) replaySame = false;
    if (!replaySame) {
        fprintf(stderr, "ns fixture: replay diverged from the original run\n");
        return 1;
    }

    FILE* nf = fopen(argv[2], "wb");
    if (!nf) { perror("fopen ns fixture"); return 1; }
    fprintf(nf, "CCNS\t1\n");
    for (int k = 0; k < kStepCount; ++k) {
        fprintf(nf, "step\t%s\t%s\t%s\t%s\t%s\t%.6f\n",
                kSteps[k].command, kSteps[k].name, kSteps[k].params,
                kSteps[k].line, kSteps[k].assigned, measured[k]);
    }
    fprintf(nf, "names\t");
    for (size_t k = 0; k < names.size(); ++k)
        fprintf(nf, "%s%s", k ? "," : "", names[k].c_str());
    fprintf(nf, "\nreplay\tok\n");
    fclose(nf);
    printf("ns fixture: %d steps, %d objects, replay verified\n",
           kStepCount, (int)names.size());
    cc_session_destroy(s1);
    cc_session_destroy(s2);
    return 0;
}
