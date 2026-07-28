#!/usr/bin/env python3
"""
Architecture-diagram generator for the regional-dr-example README.

Each diagram is defined as a compact spec (groups / nodes / edges) and emitted as a
`.drawio.svg` file: a clean SVG that GitHub renders inline in the README AND that
carries the editable draw.io model in its root `content` attribute, so the same file
opens and edits in https://app.diagrams.net . One source of truth, no drift.

Run:  python3 docs/diagrams/gen_diagrams.py
Out:  docs/images/diagrams/*.drawio.svg
"""
import html
import os
import xml.sax.saxutils as sx

OUT = os.path.join(os.path.dirname(__file__), "..", "images", "diagrams")

# ---- palette (light fills + dark text; each diagram sits on its own light canvas
#      so it stays legible in both light and dark GitHub themes) --------------------
PAL = {
    "canvas":  ("#ffffff", "#c9d1d9"),
    "group":   ("#f6f8fa", "#8b949e"),
    "hub":     ("#dbeafe", "#2563eb"),
    "spoke":   ("#dcfce7", "#16a34a"),
    "storage": ("#ffedd5", "#ea580c"),
    "net":     ("#ede9fe", "#7c3aed"),
    "policy":  ("#fef9c3", "#ca8a04"),
    "app":     ("#ccfbf1", "#0d9488"),
    "vm":      ("#cffafe", "#0891b2"),
    "ext":     ("#fce7f3", "#db2777"),
    "muted":   ("#eef1f5", "#6b7280"),
}
FONT = "Helvetica, Arial, sans-serif"


def esc(s):
    return html.escape(s, quote=True)


def _wrap_tspans(label, cx, y, w, size, color, weight="normal"):
    lines = label.split("\n")
    lh = size + 4
    total = lh * len(lines)
    start = y - total / 2 + size
    out = []
    for i, ln in enumerate(lines):
        out.append(
            f'<text x="{cx:.0f}" y="{start + i*lh:.0f}" font-family="{FONT}" '
            f'font-size="{size}" fill="{color}" text-anchor="middle" '
            f'font-weight="{weight}">{esc(ln)}</text>'
        )
    return "\n".join(out)


def _rect_edge_point(n, tx, ty):
    """Point on node n's border along the line from its center to (tx,ty)."""
    cx, cy = n["x"] + n["w"] / 2, n["y"] + n["h"] / 2
    dx, dy = tx - cx, ty - cy
    if dx == 0 and dy == 0:
        return cx, cy
    hw, hh = n["w"] / 2, n["h"] / 2
    sx_ = hw / abs(dx) if dx else float("inf")
    sy_ = hh / abs(dy) if dy else float("inf")
    s = min(sx_, sy_)
    return cx + dx * s, cy + dy * s


class Diagram:
    def __init__(self, name, title, w, h):
        self.name = name
        self.title = title
        self.w = w
        self.h = h
        self.groups = []
        self.nodes = {}
        self.order = []
        self.edges = []
        self.notes = []

    def group(self, gid, x, y, w, h, label, kind="group"):
        self.groups.append(dict(id=gid, x=x, y=y, w=w, h=h, label=label, kind=kind))

    def node(self, nid, x, y, w, h, label, kind="spoke", size=12):
        self.nodes[nid] = dict(id=nid, x=x, y=y, w=w, h=h, label=label, kind=kind, size=size)
        self.order.append(nid)

    def edge(self, a, b, label="", style="solid", color="#57606a", pts=None):
        self.edges.append(dict(a=a, b=b, label=label, style=style, color=color, pts=pts or []))

    def note(self, x, y, text, size=11, color="#6b7280", anchor="start"):
        self.notes.append(dict(x=x, y=y, text=text, size=size, color=color, anchor=anchor))

    # ---- SVG rendering --------------------------------------------------------
    def _svg_body(self):
        s = []
        cbg, cbd = PAL["canvas"]
        s.append(f'<rect x="0" y="0" width="{self.w}" height="{self.h}" rx="10" '
                 f'fill="{cbg}" stroke="{cbd}" stroke-width="1"/>')
        s.append(f'<text x="{self.w/2:.0f}" y="34" font-family="{FONT}" font-size="19" '
                 f'font-weight="bold" fill="#1f2328" text-anchor="middle">{esc(self.title)}</text>')
        # groups (behind)
        for g in self.groups:
            fill, stroke = PAL.get(g["kind"], PAL["group"])
            s.append(f'<rect x="{g["x"]}" y="{g["y"]}" width="{g["w"]}" height="{g["h"]}" rx="10" '
                     f'fill="{fill}" stroke="{stroke}" stroke-width="1.5" stroke-dasharray="6 4" opacity="0.9"/>')
            s.append(f'<text x="{g["x"]+12}" y="{g["y"]+22}" font-family="{FONT}" font-size="13" '
                     f'font-weight="bold" fill="{stroke}">{esc(g["label"])}</text>')
        # edge lines (labels are a separate pass, drawn AFTER nodes so boxes never cover them)
        edge_labels = []
        for e in self.edges:
            na, nb = self.nodes[e["a"]], self.nodes[e["b"]]
            if e["pts"]:
                p0 = _rect_edge_point(na, *e["pts"][0])
                p1 = _rect_edge_point(nb, *e["pts"][-1])
                pts = [p0] + e["pts"] + [p1]
                lx, ly = e["pts"][len(e["pts"]) // 2]           # anchor label at middle waypoint
            else:
                ca = (nb["x"] + nb["w"] / 2, nb["y"] + nb["h"] / 2)
                cb = (na["x"] + na["w"] / 2, na["y"] + na["h"] / 2)
                pts = [_rect_edge_point(na, *ca), _rect_edge_point(nb, *cb)]
                lx, ly = (pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2
            dash = 'stroke-dasharray="7 5"' if e["style"] == "dashed" else ""
            path = " ".join((f"M {x:.0f} {y:.0f}" if i == 0 else f"L {x:.0f} {y:.0f}")
                            for i, (x, y) in enumerate(pts))
            s.append(f'<path d="{path}" fill="none" stroke="{e["color"]}" stroke-width="2" '
                     f'{dash} marker-end="url(#arrow)"/>')
            if e["label"]:
                edge_labels.append((lx, ly, e["label"], e["color"]))
        # nodes
        for nid in self.order:
            n = self.nodes[nid]
            fill, stroke = PAL.get(n["kind"], PAL["spoke"])
            s.append(f'<rect x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" rx="8" '
                     f'fill="{fill}" stroke="{stroke}" stroke-width="1.8"/>')
            s.append(_wrap_tspans(n["label"], n["x"] + n["w"] / 2, n["y"] + n["h"] / 2,
                                  n["w"], n["size"], "#1f2328", "600"))
        # edge labels on top
        for lx, ly, lbl, color in edge_labels:
            tw = max(len(x) for x in lbl.split("\n")) * 6.3 + 12
            th = 15 * len(lbl.split("\n")) + 6
            s.append(f'<rect x="{lx-tw/2:.0f}" y="{ly-th/2:.0f}" width="{tw:.0f}" height="{th:.0f}" '
                     f'rx="4" fill="#ffffff" stroke="{color}" stroke-width="1" opacity="0.96"/>')
            s.append(_wrap_tspans(lbl, lx, ly, tw, 11, "#1f2328"))
        # notes
        for nt in self.notes:
            s.append(_wrap_tspans(nt["text"], nt["x"], nt["y"], 400, nt["size"], nt["color"])
                     if "\n" in nt["text"] else
                     f'<text x="{nt["x"]}" y="{nt["y"]}" font-family="{FONT}" font-size="{nt["size"]}" '
                     f'fill="{nt["color"]}" text-anchor="{nt["anchor"]}">{esc(nt["text"])}</text>')
        return "\n".join(s)

    # ---- editable draw.io model (embedded in the SVG content attribute) -------
    def _mxgraph(self):
        cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
        def style(kind, dashed=False, group=False):
            fill, stroke = PAL.get(kind, PAL["spoke"])
            base = (f"rounded=1;whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"
                    f"fontColor=#1f2328;")
            if group:
                base += "dashed=1;verticalAlign=top;fontStyle=1;align=left;spacingLeft=8;"
            if dashed:
                base += "dashed=1;"
            return base
        gid = 2
        idmap = {}
        for g in self.groups:
            cells.append(
                f'<mxCell id="g{gid}" value="{esc(g["label"])}" style="{style(g["kind"], group=True)}" '
                f'vertex="1" parent="1"><mxGeometry x="{g["x"]}" y="{g["y"]}" width="{g["w"]}" '
                f'height="{g["h"]}" as="geometry"/></mxCell>')
            gid += 1
        for nid in self.order:
            n = self.nodes[nid]
            idmap[nid] = f"n_{nid}"
            cells.append(
                f'<mxCell id="{idmap[nid]}" value="{esc(n["label"])}" style="{style(n["kind"])}" '
                f'vertex="1" parent="1"><mxGeometry x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" '
                f'height="{n["h"]}" as="geometry"/></mxCell>')
        i = 0
        for e in self.edges:
            dashed = e["style"] == "dashed"
            est = (f"edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;"
                   f"strokeColor={e['color']};fontColor=#1f2328;" + ("dashed=1;" if dashed else ""))
            cells.append(
                f'<mxCell id="e{i}" value="{esc(e["label"])}" style="{est}" edge="1" parent="1" '
                f'source="{idmap[e["a"]]}" target="{idmap[e["b"]]}"><mxGeometry relative="1" '
                f'as="geometry"/></mxCell>')
            i += 1
        model = (f'<mxGraphModel dx="800" dy="600" grid="1" gridSize="10" guides="1" '
                 f'tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" '
                 f'math="0" shadow="0"><root>{"".join(cells)}</root></mxGraphModel>')
        return f'<mxfile><diagram name="{esc(self.title)}">{model}</diagram></mxfile>'

    def render(self):
        content = html.escape(self._mxgraph(), quote=True)  # valid inside content="..."
        svg = (
            f'<svg xmlns="http://www.w3.org/2000/svg" '
            f'xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}" '
            f'content="{content}">\n'
            f'<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
            f'markerHeight="7" orient="auto-start-reverse">'
            f'<path d="M 0 0 L 10 5 L 0 10 z" fill="#57606a"/></marker></defs>\n'
            f'{self._svg_body()}\n</svg>\n'
        )
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, self.name + ".drawio.svg")
        with open(path, "w") as f:
            f.write(svg)
        return path


# =====================================================================================
#  DIAGRAM SPECS
# =====================================================================================
def d_topology():
    d = Diagram("00-topology", "Cluster topology (common substrate for all use cases)", 980, 540)
    d.group("hub", 300, 60, 380, 150, "Hub — cluster1 (management)", "hub")
    d.node("acm", 320, 96, 160, 44, "RHACM\nplacements + policies", "hub", 11)
    d.node("gitops", 495, 96, 165, 44, "OpenShift GitOps\n(ArgoCD)", "hub", 11)
    d.node("odfhub", 320, 150, 160, 40, "ODF Multicluster\nOrchestrator / Ramen", "hub", 10)
    d.node("s3note", 495, 150, 165, 40, "hub kubeconfig drives\nall spokes via oc", "muted", 10)

    d.group("s2", 60, 270, 380, 220, "Spoke — cluster2 (primary)", "spoke")
    d.node("cnv2", 90, 306, 150, 40, "OpenShift\nVirtualization", "vm", 11)
    d.node("odf2", 260, 306, 150, 40, "ODF / Ceph\n(block + CephFS)", "storage", 11)
    d.node("work2", 90, 360, 150, 44, "VM / DB / app\nworkloads", "app", 11)
    d.node("sm2", 260, 360, 150, 44, "Submariner\ngateway", "net", 11)

    d.group("s3", 540, 270, 380, 220, "Spoke — cluster3 (secondary)", "spoke")
    d.node("cnv3", 570, 306, 150, 40, "OpenShift\nVirtualization", "vm", 11)
    d.node("odf3", 740, 306, 150, 40, "ODF / Ceph\n(block + CephFS)", "storage", 11)
    d.node("work3", 570, 360, 150, 44, "VM / DB / app\nworkloads", "app", 11)
    d.node("sm3", 740, 360, 150, 44, "Submariner\ngateway", "net", 11)

    d.edge("acm", "cnv2", "manage +\nplace", "dashed", "#2563eb", pts=[(250, 248)])
    d.edge("gitops", "cnv3", "deploy", "dashed", "#2563eb", pts=[(720, 248)])
    d.edge("sm2", "sm3", "encrypted\npod network", "solid", "#7c3aed", pts=[(490, 382)])
    d.edge("odf2", "odf3", "Regional-DR\nmirroring", "solid", "#ea580c", pts=[(490, 250)])
    d.note(490, 520, "Everything runs from a Podman container via ./ansible-runner.sh — clusters are inventory hosts; work is delegated to localhost + oc.",
           11, "#6b7280", "middle")
    return d


def d_uc6():
    d = Diagram("05-cnpg-rhsi", "Use case 5 — CNPG cross-site Postgres over RHSI", 1000, 620)
    d.group("hub", 330, 56, 340, 150, "Hub — cluster1 (ACM)", "hub")
    d.node("relay", 350, 92, 300, 46, "cnpg-hub-relay policy\nManagedClusterView per spoke", "policy", 10)
    d.node("cm", 350, 148, 300, 44, "cnpg-dr-config ConfigMap\nactiveSite / currentPrimary / promotionToken", "policy", 9)

    d.group("s2", 40, 250, 420, 320, "Spoke cluster2   (pg-role=active)", "spoke")
    d.node("app2", 70, 288, 170, 46, "pg-app\nwrite→pg-write, read→pg-r", "app", 10)
    d.node("lis2", 70, 350, 170, 40, "Listener  pg-write", "net", 11)
    d.node("con2", 70, 404, 170, 40, "Connector pg-write\n→ local primary", "net", 10)
    d.node("pri2", 265, 330, 170, 90, "CNPG  pg  (PRIMARY)\nread-write\npg-rw / pg-ro / pg-r", "vm", 11)

    d.group("s3", 540, 250, 420, 320, "Spoke cluster3   (pg-role=standby)", "spoke")
    d.node("app3", 750, 288, 180, 46, "pg-app\nwrite→pg-write, read→pg-r", "app", 10)
    d.node("lis3", 750, 350, 180, 40, "Listener  pg-write", "net", 11)
    d.node("rep3", 560, 330, 170, 90, "CNPG  pg  (REPLICA)\nread-only\nstreaming", "vm", 11)

    d.edge("app2", "lis2", "", "solid", "#0d9488")
    d.edge("lis2", "con2", "", "solid", "#7c3aed")
    d.edge("con2", "pri2", "", "solid", "#7c3aed")
    d.edge("app3", "lis3", "", "solid", "#0d9488")
    d.edge("rep3", "lis3", "", "dashed", "#0891b2")
    d.edge("lis3", "con2", "RHSI mTLS VAN  (pg-write)\nSkupper Link", "solid", "#7c3aed",
           pts=[(660, 500), (400, 500), (150, 500)])
    d.edge("relay", "pri2", "read .status", "dashed", "#ca8a04", pts=[(300, 300)])
    d.edge("cm", "rep3", "promotionToken", "dashed", "#ca8a04", pts=[(690, 300)])
    d.note(500, 600, "Flip pg-role on the hub → controlled switchover (zero data loss): cluster3 promotes with the relayed demotionToken and the pg-write Connector follows.",
           11, "#6b7280", "middle")
    return d


def d_uc1():
    d = Diagram("01-regional-dr", "Use case 1 — Regional DR failover (ODF Regional-DR + Ramen)", 980, 560)
    d.group("hub", 310, 54, 360, 150, "Hub — cluster1 (ACM)", "hub")
    d.node("drpc", 330, 90, 320, 48, "DRPlacementControl + DRPolicy\n(Ramen)", "policy", 11)
    d.node("place", 330, 146, 320, 40, "ACM Placement\n(schedules the workload)", "hub", 10)

    d.group("s2", 40, 246, 400, 280, "Spoke cluster2 (primary — VM running)", "spoke")
    d.node("vm2", 75, 300, 150, 60, "VM\nvm-dr-example\n(Running)", "vm", 11)
    d.node("pvc2", 75, 378, 150, 48, "PVC (RBD,\nmirror-enabled)", "storage", 10)
    d.node("odf2", 250, 320, 160, 106, "ODF / Ceph\nRBD async\nmirror", "storage", 11)

    d.group("s3", 540, 246, 400, 280, "Spoke cluster3 (secondary — standby)", "spoke")
    d.node("odf3", 570, 320, 160, 106, "ODF / Ceph\nRBD async\nmirror", "storage", 11)
    d.node("pvc3", 760, 378, 150, 48, "PVC\n(replicated)", "storage", 10)
    d.node("vm3", 760, 300, 150, 60, "VM\n(restarted on\nfailover)", "muted", 10)

    d.edge("vm2", "pvc2", "", "solid", "#0d9488")
    d.edge("pvc2", "odf2", "", "solid", "#ea580c")
    d.edge("odf2", "odf3", "RBD mirror\n(async)", "solid", "#ea580c", pts=[(490, 300)])
    d.edge("odf3", "pvc3", "", "solid", "#ea580c")
    d.edge("pvc3", "vm3", "restart on\nfailover", "dashed", "#6b7280")
    d.edge("drpc", "vm2", "place", "dashed", "#2563eb", pts=[(250, 232)])
    d.edge("drpc", "vm3", "failover", "dashed", "#2563eb", pts=[(730, 232)])
    d.note(490, 546, "DRPC Failover restarts the VM on cluster3 from the mirror-replicated storage — recovery, not live (the VM is down during the switch).",
           11, "#6b7280", "middle")
    return d


def d_uc2():
    d = Diagram("02-cclm", "Use case 2 — Cross-cluster live migration (CCLM) over Submariner", 980, 520)
    d.group("hub", 340, 52, 300, 108, "Hub — cluster1 (ACM)", "hub")
    d.node("mig", 360, 86, 260, 60, "ACM / KubeVirt\nVirtualMachineInstance\nMigration", "policy", 10)

    d.group("s2", 40, 220, 340, 240, "Spoke cluster2 (source)", "spoke")
    d.node("vm2", 90, 300, 240, 96, "VM  cclm-fedora\n(Running —\nnever stops)", "vm", 12)

    d.group("s3", 600, 220, 340, 240, "Spoke cluster3 (target)", "spoke")
    d.node("vm3", 650, 300, 240, 96, "VM  cclm-fedora\n(Running\nafter migration)", "vm", 12)

    d.node("net", 410, 312, 160, 72, "Submariner\nencrypted\npod network", "net", 11)

    d.edge("vm2", "net", "", "solid", "#7c3aed")
    d.edge("net", "vm3", "memory + disk\nmove live", "solid", "#7c3aed")
    d.edge("mig", "net", "initiate", "dashed", "#2563eb", pts=[(490, 250)])
    d.note(490, 500, "Decentralized live migration over the Submariner pod network — the VM keeps running while its memory and disk move. Needs non-overlapping CIDRs, globalnet off.",
           11, "#6b7280", "middle")
    return d


def d_uc3():
    d = Diagram("03-volsync-dr", "Use case 3 — VolSync Direct DR over Submariner, app or VM (label-flip failover, no Ramen)", 980, 610)
    d.group("hub", 300, 44, 400, 170, "Hub — cluster1 (ACM)", "hub")
    d.node("pol", 320, 80, 360, 50, "ACM policies — app-role active/standby\n(Placements swap RS ↔ RD roles)", "policy", 10)
    d.node("mcv", 320, 138, 360, 46, "ManagedClusterView → hub ConfigMap\n(dest address + keySecret)", "hub", 10)

    d.group("s2", 40, 254, 370, 274, "Spoke cluster2 (app-role=active)", "spoke")
    d.node("app2", 58, 296, 155, 56, "app + PVC\nmysql-pvc", "app", 10)
    d.node("vm2", 227, 296, 155, 56, "VM vm-dr-example\n+ vm-data-pvc", "vm", 10)
    d.node("rs2", 135, 396, 160, 50, "ReplicationSource\nrsync-tls mover", "net", 10)

    d.group("s3", 570, 254, 370, 274, "Spoke cluster3 (app-role=standby)", "spoke")
    d.node("pvc3", 598, 296, 155, 56, "PVC + VolumeSnapshot\nmysql-pvc / vm-data-pvc", "storage", 9)
    d.node("wl3", 767, 296, 155, 56, "app or VM starts\nhere on failover", "muted", 10)
    d.node("rd3", 675, 396, 160, 50, "ReplicationDestination\nrsync-tls mover", "net", 10)

    d.node("sm", 425, 388, 130, 66, "Submariner\nclusterset\n(no globalnet)", "net", 10)

    d.edge("app2", "rs2", "", "solid", "#0d9488")
    d.edge("vm2", "rs2", "", "solid", "#0891b2")
    d.edge("rs2", "sm", "rsync-tls", "solid", "#7c3aed")
    d.edge("sm", "rd3", "<svc>.<ns>.svc\n.clusterset.local", "solid", "#7c3aed")
    d.edge("rd3", "pvc3", "snapshot", "solid", "#ea580c")
    d.edge("pvc3", "wl3", "", "dashed", "#6b7280")
    d.edge("pol", "rs2", "enforce\n(active)", "dashed", "#ca8a04", pts=[(250, 240)])
    d.edge("pol", "rd3", "enforce\n(standby)", "dashed", "#ca8a04", pts=[(730, 240)])
    d.note(490, 560, "Failover = flip app-role on the hub: GitOps moves the workload onto the new active spoke and the policies swap ReplicationSource/Destination. No Ramen / ODF mirror.\n"
                     "Two variants, deploy one at a time: volsync-dr = app + mysql-pvc; volsync-dr --vm = Fedora VM vm-dr-example + vm-data-pvc (own namespace, vm-vs-* policy twins).\n"
                     "The rsync-tls path rides the Submariner clusterset: a ClusterIP Service + ServiceExport, resolved as <svc>.<ns>.svc.clusterset.local.\n"
                     "Set volsync_use_submariner=false to use a LoadBalancer address instead (no Submariner).",
           11, "#6b7280", "middle")
    return d


def d_uc5():
    d = Diagram("04-oadp", "Use case 4 — OADP backup & recovery to object storage", 980, 560)
    d.group("hub", 330, 50, 320, 112, "Hub — cluster1 (ACM)", "hub")
    d.node("sched", 350, 84, 280, 60, "ACM policy →\nVelero Schedule per VM\nlabelled oadp-backup", "policy", 10)

    d.group("s2", 40, 210, 340, 250, "Spoke cluster2 (backup)", "spoke")
    d.node("vm2", 95, 262, 230, 60, "VM (Running)", "vm", 12)
    d.node("oadp2", 95, 344, 230, 64, "OADP / Velero\nCSI snapshot + data mover", "storage", 10)

    d.group("s3", 600, 210, 340, 250, "Spoke cluster3 (restore)", "spoke")
    d.node("vm3", 655, 262, 230, 60, "VM (recovered)", "muted", 12)
    d.node("oadp3", 655, 344, 230, 64, "OADP / Velero\nrestore", "storage", 10)

    d.node("s3b", 405, 400, 170, 84, "S3 bucket\n(object storage,\ncross-account)", "ext", 11)

    d.edge("vm2", "oadp2", "", "solid", "#0d9488")
    d.edge("oadp2", "s3b", "backup\n(snapshot + move)", "solid", "#db2777")
    d.edge("s3b", "oadp3", "restore", "solid", "#db2777")
    d.edge("oadp3", "vm3", "", "solid", "#0d9488")
    d.edge("sched", "oadp2", "schedule\n5-min, 1h TTL", "dashed", "#ca8a04", pts=[(250, 195)])
    d.note(490, 544, "Backups (on-demand or scheduled) land in a normal S3 bucket, so recovery works cross-cluster, cross-region, even off-cluster.",
           11, "#6b7280", "middle")
    return d


DIAGRAMS = [d_topology, d_uc1, d_uc2, d_uc3, d_uc5, d_uc6]

if __name__ == "__main__":
    for fn in DIAGRAMS:
        p = fn().render()
        print("wrote", os.path.relpath(p))
