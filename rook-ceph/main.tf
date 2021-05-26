# The parent module must define a helm provider which will be used here to apply the helm chart
resource "helm_release" "rook_ceph" {
  name             = "rook-ceph"
  namespace        = "rook-ceph"
  create_namespace = true
  repository       = "https://charts.rook.io/release"
  chart            = "rook-ceph"
}

locals {

  rook_vault_token = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "rook-vault-token"
      namespace = "rook-ceph # namespace:cluster"
    }
    data = {
      token = "ROOK_TOKEN_CHANGE_ME"
    }
  }

  rook_ceph_block_pool = {
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephBlockPool"
    metadata = {
      name      = "replicapool"
      namespace = "rook-ceph"
    }
    spec = {
      failureDomain = "host"
      replicated = {
        size = 3
        # Disallow setting pool with replica 1, this could lead to data loss without recovery.
        # Make sure you're *ABSOLUTELY CERTAIN* that is what you want
        requireSafeReplicaSize = true
        # gives a hint (%) to Ceph in terms of expected consumption of the total cluster capacity of a given pool
        # for more info = "https://docs.ceph.com/docs/master/rados/operations/placement-groups/#specifying-expected-pool-size
        #targetSizeRatio = ".5"
      }
    }
  }

  rook_ceph_block_storageclass = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "rook-ceph-block"
    }
    # Change "rook-ceph" provisioner prefix to match the operator namespace if needed
    provisioner = "rook-ceph.rbd.csi.ceph.com"
    parameters = {
      # clusterID is the namespace where the rook cluster is running
      # If you change this namespace, also change the namespace below where the secret namespaces are defined
      clusterID = "rook-ceph" # namespace:cluster

      # If you want to use erasure coded pool with RBD, you need to create
      # two pools. one erasure coded and one replicated.
      # You need to specify the replicated pool here in the `pool` parameter, it is
      # used for the metadata of the images.
      # The erasure coded pool must be set as the `dataPool` parameter below.
      #dataPool = "ec-data-pool"
      pool = "replicapool"

      # (optional) mapOptions is a comma-separated list of map options.
      # For krbd options refer
      # https://docs.ceph.com/docs/master/man/8/rbd/#kernel-rbd-krbd-options
      # For nbd options refer
      # https://docs.ceph.com/docs/master/man/8/rbd-nbd/#options
      # mapOptions = "lock_on_read,queue_depth=1024"

      # (optional) unmapOptions is a comma-separated list of unmap options.
      # For krbd options refer
      # https://docs.ceph.com/docs/master/man/8/rbd/#kernel-rbd-krbd-options
      # For nbd options refer
      # https://docs.ceph.com/docs/master/man/8/rbd-nbd/#options
      # unmapOptions = "force"

      # RBD image format. Defaults to "2".
      imageFormat = "2"

      # RBD image features. Available for imageFormat = ""2". CSI RBD currently supports only `layering` feature.
      imageFeatures = "layering"

      # The secrets contain Ceph admin credentials. These are generated automatically by the operator
      # in the same namespace as the cluster.
      "csi.storage.k8s.io/provisioner-secret-name"            = "rook-csi-rbd-provisioner"
      "csi.storage.k8s.io/provisioner-secret-namespace"       = "rook-ceph" # namespace:cluster
      "csi.storage.k8s.io/controller-expand-secret-name"      = "rook-csi-rbd-provisioner"
      "csi.storage.k8s.io/controller-expand-secret-namespace" = "rook-ceph" # namespace:cluster
      "csi.storage.k8s.io/node-stage-secret-name"             = "rook-csi-rbd-node"
      "csi.storage.k8s.io/node-stage-secret-namespace"        = "rook-ceph" # namespace:cluster
      # Specify the filesystem type of the volume. If not specified, csi-provisioner
      # will set default as `ext4`. Note that `xfs` is not recommended due to potential deadlock
      # in hyperconverged settings where the volume is mounted on the same node as the osds.
      "csi.storage.k8s.io/fstype" = "ext4"
    }
    # uncomment the following to use rbd-nbd as mounter on supported nodes
    # **IMPORTANT** = "If you are using rbd-nbd as the mounter, during upgrade you will be hit a ceph-csi
    # issue that causes the mount to be disconnected. You will need to follow special upgrade steps
    # to restart your application pods. Therefore, this option is not recommended.
    #mounter = "rbd-nbd"
    allowVolumeExpansion = true
    reclaimPolicy        = "Delete"
  }

  rook_ceph_fs_storageclass = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "rook-cephfs"
    }
    provisioner = "rook-ceph.cephfs.csi.ceph.com" # driver:namespace:operator
    parameters = {
      # clusterID is the namespace where operator is deployed.
      clusterID = "rook-ceph" # namespace:cluster

      # CephFS filesystem name into which the volume shall be created
      fsName = "myfs"

      # Ceph pool into which the volume shall be created
      # Required for provisionVolume: "true"
      pool = "myfs-data0"

      # The secrets contain Ceph admin credentials. These are generated automatically by the operator
      # in the same namespace as the cluster.
      "csi.storage.k8s.io/provisioner-secret-name"            = "rook-csi-cephfs-provisioner"
      "csi.storage.k8s.io/provisioner-secret-namespace"       = "rook-ceph" # namespace:cluster
      "csi.storage.k8s.io/controller-expand-secret-name"      = "rook-csi-cephfs-provisioner"
      "csi.storage.k8s.io/controller-expand-secret-namespace" = "rook-ceph" # namespace:cluster
      "csi.storage.k8s.io/node-stage-secret-name"             = "rook-csi-cephfs-node"
      "csi.storage.k8s.io/node-stage-secret-namespace"        = "rook-ceph" # namespace:cluster

      # (optional) The driver can use either ceph-fuse (fuse) or ceph kernel client (kernel)
      # If omitted, default volume mounter will be used - this is determined by probing for ceph-fuse
      # or by setting the default mounter explicitly via --volumemounter command-line argument.
      # mounter = "kernel"
    }
    reclaimPolicy        = "Delete"
    allowVolumeExpansion = true
    mountOptions = [
      # uncomment the following line for debugging
      # debug
    ]
  }
}

# UNCOMMENT THIS TO ENABLE A KMS CONNECTION
# Also, do not forget to replace both:
#   * ROOK_TOKEN_CHANGE_ME: with a base64 encoded value of the token to use
#   * VAULT_ADDR_CHANGE_ME: with the Vault address
# resource "kubectl_manifest" "rook_vault_token" {
#   yaml_body = yamlencode(local.rook_vault_token)
# }

resource "kubectl_manifest" "ceph_cluster" {
  yaml_body = var.ceph_cloud_storage_spec == null ? yamlencode(local.ceph_cluster_local) : yamlencode(local.ceph_cluster_cloud)

  depends_on = [
    helm_release.rook_ceph
  ]
}

resource "kubectl_manifest" "rook_ceph_block_pool" {
  yaml_body = yamlencode(local.rook_ceph_block_pool)

  depends_on = [
    kubectl_manifest.ceph_cluster
  ]
}

resource "kubectl_manifest" "rook_ceph_block_storageclass" {
  yaml_body = yamlencode(local.rook_ceph_block_storageclass)

  depends_on = [
    kubectl_manifest.rook_ceph_block_pool
  ]
}

resource "kubectl_manifest" "rook_ceph_fs_storageclass" {
  yaml_body = yamlencode(local.rook_ceph_fs_storageclass)
  depends_on = [
    kubectl_manifest.ceph_cluster
  ]
}
