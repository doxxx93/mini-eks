# mini-eks

Build a managed Kubernetes service that gives users what EKS gives them: by hand first, then as controllers in both Go and Rust. Private GitHub repo `doxxx93/mini-eks`.

- `STEPS.md` is the single linear checklist. When the user asks what's next, name only the first unchecked step instead of offering a menu.
- Each step ends with a Korean note `notes/NN-*.md` following `notes/TEMPLATE.md`. Notes are the user's learning record: draft or review as they ask, and always fact-check the "실제 EKS·GKE에서는" section against docs or source, with links.
- Go and Rust implement the same CRDs and must pass the same language-neutral checks. Go goes first; Rust follows.
- Layout: one `main` branch, split by directory. `manual/NN-slug/` holds each phase 1 step's manifests and commands (only that step's delta; the cluster state carries over from earlier steps). `api/` is the shared CRD YAML, `test/` the language-neutral checks, `go/` and `rust/` the two evolving implementations. When a step is done, tag `step-NN` on main. Branches are only short-lived per-step workspaces (e.g. an Orca worktree) merged back into main.
- Tools: `mise.toml` pins kubectl 1.37 and kind 0.33.0 (kind's default node image is v1.37.0). OrbStack's bundled kubectl 1.33 at `/usr/local/bin/kubectl` is outside the one-minor skew, so run commands from inside this directory where mise wins on PATH. etcdctl ships inside the etcd image; no extra host tools are needed for phase 1.
- Environment: OrbStack Docker + kind for phases 1–4. Lima (vz, nestedVirtualization; needs Apple M3 or later) + KubeVirt only from phase 5.
