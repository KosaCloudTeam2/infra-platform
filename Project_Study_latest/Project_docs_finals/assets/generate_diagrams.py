#!/usr/bin/env python3
"""KOSA Team2 인프라 다이어그램 생성. python3 generate_diagrams.py
NOTE: 라벨은 영어로 (CJK 폰트 의존성 회피). 한글 설명은 markdown 캡션 활용."""
import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))

from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.network import Pfsense, Haproxy, Internet
from diagrams.onprem.compute import Server
from diagrams.onprem.container import Docker
from diagrams.onprem.gitops import Argocd
from diagrams.onprem.ci import Jenkins
from diagrams.onprem.vcs import Github
from diagrams.onprem.registry import Harbor
from diagrams.onprem.storage import Ceph, CephOsd
from diagrams.onprem.certificates import CertManager
from diagrams.k8s.compute import Pod, Deployment
from diagrams.k8s.controlplane import APIServer
from diagrams.k8s.network import Ingress, Service
from diagrams.k8s.infra import Master, Node, ETCD
from diagrams.generic.network import Switch, Router
from diagrams.generic.device import Mobile

GA = {"fontsize": "16", "bgcolor": "white", "pad": "0.5", "splines": "spline"}


# 01-big-picture
with Diagram("KOSA Team2 - Full System Topology",
             filename="01-big-picture", show=False, direction="TB", graph_attr=GA):
    internet = Internet("Internet\n(External Users)")

    with Cluster("WAN / Edge"):
        router = Router("Router\n192.168.21.1")
        pf = Pfsense("pfSense HA\n(CARP+pfsync)")

    with Cluster("VLAN 20 - DMZ"):
        edge_vip = Haproxy("Edge HAProxy x2\nVIP 172.16.22.5\n(1st TLS termination)")

    with Cluster("VLAN 30 - K8s Cluster"):
        api_vip = Haproxy("lb-1/lb-2\nAPI VIP 172.16.23.5")
        with Cluster("Control Plane x 3"):
            cps = [Master("cp1"), Master("cp2"), Master("cp3")]
        with Cluster("Workers"):
            sys = Node("sys1 (16GB)\nworkload=system")
            prods = Node("w1/w2/w3\nworkload=production")
        ingress_lb = Service("MetalLB\n172.16.23.50\n(2nd TLS termination)")

    with Cluster("Ceph 10G Fabric"):
        ceph = Ceph("Ceph 6-Node\n6x1TB HDD\nRBD + RGW S3")

    internet >> router >> pf
    pf >> edge_vip >> ingress_lb
    ingress_lb >> sys
    ingress_lb >> prods
    cps >> Edge(style="dashed") >> api_vip
    sys >> Edge(style="dotted", color="gray") >> ceph
    prods >> Edge(style="dotted", color="gray") >> ceph


# 01-traffic-flow
with Diagram("External Traffic Flow - Double TLS",
             filename="01-traffic-flow", show=False, direction="LR", graph_attr=GA):
    user = Mobile("User\nhttps://ticket.kosa.team2")
    pf_n = Pfsense("pfSense NAT\n192.168.21.109\n-> 172.16.22.5")
    edge = Haproxy("Edge HAProxy\nwildcard *.kosa.team2\n(1st TLS term)")
    ing_lb = Service("MetalLB\n172.16.23.50")
    ing_ctl = Ingress("HAProxy Ingress\ncert-manager cert\n(2nd TLS term)")
    svc = Service("Service\nClusterIP")
    pod = Pod("ticket-app Pod")

    user >> Edge(label="(1) HTTPS") >> pf_n
    pf_n >> Edge(label="(2) HTTPS") >> edge
    edge >> Edge(label="(3) HTTPS\nre-encrypt") >> ing_lb
    ing_lb >> ing_ctl
    ing_ctl >> Edge(label="(4) HTTP") >> svc >> pod


# 02-network-topology
with Diagram("Physical/Logical Network - 4 VLANs + pfSense HA",
             filename="02-network-topology", show=False, direction="TB", graph_attr=GA):
    inet = Internet("Internet")
    router = Router("Router 192.168.21.1")

    with Cluster("Management (192.168.21.0/24)"):
        mgmt = Switch("1G Mgmt Switch")
        prox = Server("Proxmox x4\nkosa1~4")

    with Cluster("pfSense HA (Proxmox VM)"):
        pf_p = Pfsense("Primary\nMASTER")
        pf_b = Pfsense("Secondary\nBACKUP")
        pf_p - Edge(label="pfsync\nXMLRPC", style="dashed", color="orange") - pf_b

    with Cluster("VLAN 10 - Mgmt 172.16.21/24"):
        v10 = Server("IPMI/iLO\n(reserved)")
    with Cluster("VLAN 20 - DMZ 172.16.22/24"):
        v20 = Haproxy("Edge HAProxy x2\nVIP 172.16.22.5")
    with Cluster("VLAN 30 - Internal 172.16.23/24"):
        v30 = Node("K8s nodes x7\n+ lb-1/lb-2")
    with Cluster("VLAN 40 - Guest 172.16.24/24"):
        v40 = Server("bastion\n172.16.24.10")

    inet >> router >> mgmt >> prox
    router >> Edge(label="WAN", color="red") >> pf_p
    pf_p >> Edge(label="VLAN trunk", color="blue") >> v10
    pf_p >> Edge(color="blue") >> v20
    pf_p >> Edge(color="blue") >> v30
    pf_p >> Edge(color="blue") >> v40


# 02-spine-leaf
with Diagram("Spine-Leaf 10G Fabric (Ceph)",
             filename="02-spine-leaf", show=False, direction="TB", graph_attr=GA):
    with Cluster("Spine Layer"):
        spines = [Switch("Spine 1"), Switch("Spine 2")]
    with Cluster("Leaf Layer (x5)"):
        leaves = [Switch(f"Leaf {i+1}") for i in range(5)]
    for s in spines:
        for l in leaves:
            s - Edge(color="darkgreen") - l
    with Cluster("Ceph 6 nodes"):
        ceph_nodes = [CephOsd(f"ceph{i+1}\n10.10.10.{11+i}") for i in range(6)]
    with Cluster("Proxmox 4 nodes (10G NIC)"):
        prox = [Server(f"kosa{i+1}\n10.10.10.{35+i}") for i in range(4)]
    leaves[0] - ceph_nodes[0]
    leaves[0] - prox[0]
    leaves[1] - ceph_nodes[1]
    leaves[1] - prox[1]
    leaves[2] - ceph_nodes[2]
    leaves[2] - prox[2]
    leaves[3] - ceph_nodes[3]
    leaves[3] - prox[3]
    leaves[4] - ceph_nodes[4]
    leaves[4] - ceph_nodes[5]


# 03-vm-placement
with Diagram("Proxmox 4 Nodes - VM Placement (Anti-Affinity)",
             filename="03-vm-placement", show=False, direction="LR", graph_attr=GA):
    with Cluster("kosa1 (32GB)"):
        Pfsense("pfSense Primary")
        Node("k8s-sys1 (16GB)")
    with Cluster("kosa2 (32GB)"):
        Pfsense("pfSense Secondary")
        Master("k8s-cp2")
        Node("k8s-w3")
        Haproxy("lb-1")
    with Cluster("kosa3 (32GB)"):
        Master("k8s-cp3")
        Node("k8s-w1")
        Server("bastion")
        Haproxy("edge-haproxy2")
    with Cluster("kosa4 (32GB)"):
        Master("k8s-cp1")
        Node("k8s-w2")
        Haproxy("lb-2")
        Haproxy("edge-haproxy")


# 04-ceph-components
with Diagram("Ceph Cluster - Components and Clients",
             filename="04-ceph-components", show=False, direction="TB", graph_attr=GA):
    with Cluster("Clients"):
        k8s_pod = Pod("K8s Pod\n(ceph-csi-rbd)")
        harbor_app = Harbor("Harbor\n(S3 SDK)")

    with Cluster("Ceph Cluster (6 nodes)"):
        with Cluster("MON quorum (3)"):
            mons = [Server("MON1"), Server("MON2"), Server("MON3")]
        with Cluster("MGR (active+standby)"):
            mgrs = [Server("MGR active"), Server("MGR standby")]
        with Cluster("OSD (6 = 6 HDDs)"):
            osds = [CephOsd(f"osd.{i}") for i in range(6)]
        rgw = Server("RGW :7480\n(S3 Gateway)")

    k8s_pod >> Edge(label="RBD block") >> mons[0]
    for m in mons:
        m >> Edge(label="OSD lookup", style="dashed") >> osds[0]
    harbor_app >> Edge(label="S3 HTTP") >> rgw
    rgw >> Edge(style="dashed") >> osds[0]


# 05-k8s-architecture
with Diagram("Kubernetes HA - CP + Worker + API LB",
             filename="05-k8s-architecture", show=False, direction="TB", graph_attr=GA):
    user = Server("kubectl\n(bastion)")
    kubelets = Node("kubelets\n(all nodes)")

    with Cluster("API VIP 172.16.23.5"):
        lb1 = Haproxy("lb-1 MASTER\nKeepalived")
        lb2 = Haproxy("lb-2 BACKUP")
        lb1 - Edge(label="VRRP", style="dashed", color="orange") - lb2

    with Cluster("Control Plane (Stacked etcd)"):
        with Cluster("k8s-cp1"):
            cp1 = APIServer("apiserver")
            e1 = ETCD("etcd1")
            cp1 - e1
        with Cluster("k8s-cp2"):
            cp2 = APIServer("apiserver")
            e2 = ETCD("etcd2")
            cp2 - e2
        with Cluster("k8s-cp3"):
            cp3 = APIServer("apiserver")
            e3 = ETCD("etcd3")
            cp3 - e3

    with Cluster("Workers"):
        wsys = Node("k8s-sys1\nworkload=system")
        wp1 = Node("k8s-w1")
        wp2 = Node("k8s-w2")
        wp3 = Node("k8s-w3")

    user >> Edge(label="6443") >> lb1
    kubelets >> Edge(label="6443", style="dashed") >> lb1
    lb1 >> [cp1, cp2, cp3]


# 06-double-tls
with Diagram("Double TLS Termination - Cert Flow",
             filename="06-double-tls", show=False, direction="TB", graph_attr=GA):
    with Cluster("Internal CA (10 years)"):
        ca = CertManager("KOSA Team2\nInternal CA")

    with Cluster("Cert 1 - Wildcard (1 year, manual)"):
        wc = CertManager("*.kosa.team2\nwildcard.pem")

    with Cluster("Cert 2 - per-service (90 days, auto)"):
        cm = CertManager("cert-manager\nClusterIssuer")

    with Cluster("Deployment"):
        edge = Haproxy("Edge HAProxy\n1st TLS termination")
        ing = Ingress("HAProxy Ingress\n2nd TLS termination")

    ca >> Edge(label="signs") >> wc >> edge
    ca >> Edge(label="signs") >> cm >> ing
    edge >> Edge(label="HTTPS\nre-encrypt", color="blue") >> ing


# 10-cicd-pipeline
with Diagram("CI/CD Pipeline - kosa-tickets end-to-end",
             filename="10-cicd-pipeline", show=False, direction="LR", graph_attr=GA):
    dev = Mobile("Developer")
    src = Github("kosa-tickets\n(FastAPI + Dockerfile)")
    jenkins = Jenkins("Jenkins\nController")
    kaniko = Docker("Kaniko Pod\n(rootless build)")
    harbor = Harbor("Harbor\nlibrary/kosa-tickets:N")
    gitops = Github("kosa-gitops\n(deployment.yaml)")
    argo = Argocd("ArgoCD\n(pull + sync)")
    deploy = Deployment("ticket-app")
    new_pod = Pod("new Pod :N")

    dev >> Edge(label="(1) push") >> src
    dev >> Edge(label="(2) Build Now") >> jenkins
    jenkins >> Edge(label="(3) Pod create") >> kaniko
    kaniko >> Edge(label="(4) clone", style="dashed") >> src
    kaniko >> Edge(label="(5) push :N") >> harbor
    jenkins >> Edge(label="(6) sed + git push") >> gitops
    argo >> Edge(label="(7) poll") >> gitops
    argo >> Edge(label="(8) kubectl apply") >> deploy >> new_pod
    new_pod >> Edge(label="(9) pull", style="dashed", color="gray") >> harbor


print("Done - all diagrams generated")
for f in sorted(os.listdir(".")):
    if f.endswith(".png"):
        print(f"  {f} ({os.path.getsize(f)//1024} KB)")
