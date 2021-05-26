locals {
  ceph_cluster_local = {
    #################################################################################################################
    # Define the settings for the rook-ceph cluster with common settings for a production cluster.
    # All nodes with available raw devices will be used for the Ceph cluster. At least three nodes are required
    # in this example. See the documentation for more details on storage settings available.

    # For example, to create the cluster:
    #   kubectl create -f crds.yaml -f common.yaml -f operator.yaml
    #   kubectl create -f cluster-on-pvc.yaml
    #################################################################################################################
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephCluster"
    metadata = {
      name      = "rook-ceph"
      namespace = "rook-ceph" # namespace:cluster
    }
    spec = {
      # In Minikube, the '/data' directory is configured to persist across reboots. Use "/data/rook" in Minikube environment.
      dataDirHostPath = "/var/lib/rook"

      mon = {
        # Set the number of mons to be started. Must be an odd number, and is generally recommended to be 3.
        count = 3
        # The mons should be on unique nodes. For production, at least 3 nodes are recommended for this reason.
        # Mons should only be allowed on the same node for test environments where data loss is acceptable.
        allowMultiplePerNode = false
      }
      cephVersion = {
        # The container image used to launch the Ceph daemon pods (mon, mgr, osd, mds, rgw).
        # v13 is mimic, v14 is nautilus, and v15 is octopus.
        # RECOMMENDATION: In production, use a specific version tag instead of the general v14 flag, which pulls the latest release and could result in different
        # versions running within the cluster. See tags available at https://hub.docker.com/r/ceph/ceph/tags/.
        # If you want to be more precise, you can always use a timestamp tag such ceph/ceph:v15.2.11-20200419
        # This tag might not contain a new Ceph version, just security fixes from the underlying operating system, which will reduce vulnerabilities
        image = "ceph/ceph:v15.2.11"
        # Whether to allow unsupported versions of Ceph. Currently `nautilus` and `octopus` are supported.
        # Future versions such as `pacific` would require this to be set to `true`.
        # Do not set to true in production.
        allowUnsupported = false
      }
      # Whether or not upgrade should continue even if a check fails
      # This means Ceph's status could be degraded and we don't recommend upgrading but you might decide otherwise
      # Use at your OWN risk
      # To understand Rook's upgrade process of Ceph, read https://rook.io/docs/rook/master/ceph-upgrade.html#ceph-version-upgrades
      skipUpgradeChecks = false
      # Whether or not continue if PGs are not clean during an upgrade
      continueUpgradeAfterChecksEvenIfNotHealthy = false
      # WaitTimeoutForHealthyOSDInMinutes defines the time (in minutes) the operator would wait before an OSD can be stopped for upgrade or restart.
      # If the timeout exceeds and OSD is not ok to stop, then the operator would skip upgrade for the current OSD and proceed with the next one
      # if `continueUpgradeAfterChecksEvenIfNotHealthy` is `false`. If `continueUpgradeAfterChecksEvenIfNotHealthy` is `true`, then opertor would
      # continue with the upgrade of an OSD even if its not ok to stop after the timeout. This timeout won't be applied if `skipUpgradeChecks` is `true`.
      # The default wait timeout is 10 minutes.
      waitTimeoutForHealthyOSDInMinutes : 10
      mgr = {
        # When higher availability of the mgr is needed, increase the count to 2.
        # In that case, one mgr will be active and one in standby. When Ceph updates which
        # mgr is active, Rook will update the mgr services to match the active mgr.
        count = 1
        modules = [
          # Several modules should not need to be included in this list. The "dashboard" and "monitoring" modules
          # are already enabled by other settings in the cluster CR.
          {
            name    = "pg_autoscaler"
            enabled = true
          }
        ]
      }
      # enable the ceph dashboard for viewing cluster status
      dashboard = {
        enabled = true
        # serve the dashboard under a subpath (useful when you are accessing the dashboard via a reverse proxy)
        # urlPrefix: /ceph-dashboard
        # serve the dashboard at the given port.
        # port: 8443
        # serve the dashboard using SSL
        ssl = true
      }
      # enable prometheus alerting for cluster
      monitoring = {
        # requires Prometheus to be pre-installed
        enabled = false
        # namespace to deploy prometheusRule in. If empty, namespace of the cluster will be used.
        # Recommended:
        # If you have a single rook-ceph cluster, set the rulesNamespace to the same namespace as the cluster or keep it empty.
        # If you have multiple rook-ceph clusters in the same k8s cluster, choose the same namespace (ideally, namespace with prometheus
        # deployed) to set rulesNamespace for all the clusters. Otherwise, you will get duplicate alerts with multiple alert definitions.
        rulesNamespace = "rook-ceph"
      }
      # enable the crash collector for ceph daemon crash collection
      crashCollector = {
        disable = false
        # Uncomment daysToRetain to prune ceph crash entries older than the
        # specified number of days.
        #daysToRetain = 30
      }
      # enable log collector, daemons will log on files and rotate
      # logCollector = {
      #   enabled = true
      #   periodicity = "24h" # SUFFIX may be 'h' for hours or 'd' for days.
      # automate [data cleanup process](https://github.com/rook/rook/blob/master/Documentation/ceph-teardown.md#delete-the-data-on-hosts) in cluster destruction.
      # }
      cleanupPolicy = {
        # Since cluster cleanup is destructive to data, confirmation is required.
        # To destroy all Rook data on hosts during uninstall, confirmation must be set to "yes-really-destroy-data".
        # This value should only be set when the cluster is about to be deleted. After the confirmation is set,
        # Rook will immediately stop configuring the cluster and only wait for the delete command.
        # If the empty string is set, Rook will not destroy any data on hosts during uninstall.
        confirmation = ""
        # sanitizeDisks represents settings for sanitizing OSD disks on cluster deletion
        sanitizeDisks = {
          # method indicates if the entire disk should be sanitized or simply ceph's metadata
          # in both case, re-install is possible
          # possible choices are 'complete' or 'quick' (default)
          method = "quick"
          # dataSource indicate where to get random bytes from to write on the disk
          # possible choices are 'zero' (default) or 'random'
          # using random sources will consume entropy from the system and will take much more time then the zero source
          dataSource = "zero"
          # iteration overwrite N times instead of the default (1)
          # takes an integer value
          iteration = 1
        }
        # allowUninstallWithVolumes defines how the uninstall should be performed
        # If set to true, cephCluster deletion does not wait for the PVs to be deleted.
        allowUninstallWithVolumes = false
      }
      annotations = {
        #  all = ""
        #  mon = ""
        #  osd = ""
        #  cleanup = ""
        #  prepareosd = ""
        # If no mgr annotations are set, prometheus scrape annotations will be set by default.
        #    mgr = ""
      }
      labels = {
        #  all = ""
        #  mon = ""
        #  osd = ""
        #  cleanup = ""
        #  mgr = ""
        #  prepareosd = ""
        # monitoring is a list of key-value pairs. It is injected into all the monitoring resources created by operator.
        # These labels can be passed as LabelSelector to Prometheus
        #    monitoring = ""
      }
      # The option to automatically remove OSDs that are out and are safe to destroy.
      removeOSDsIfOutAndSafeToRemove = false
      #  priorityClassNames = {
      #    all = "rook-ceph-default-priority-class"
      #    mon = "rook-ceph-mon-priority-class"
      #    osd = "rook-ceph-osd-priority-class"
      #    mgr = "rook-ceph-mgr-priority-class"
      #  }

      # cluster level storage configuration and selection
      storage = {
        useAllNodes   = true
        useAllDevices = true
        #deviceFilter = ""
        config = {
          # crushRoot = "custom-root" # specify a non-default root label for the CRUSH map
          # metadataDevice = "md0" # specify a non-rotational storage so ceph-volume will use it as block db device of bluestore.
          # databaseSizeMB = "1024" # uncomment if the disks are smaller than 100 GB
          # journalSizeMB = "1024"  # uncomment if the disks are 20 GB or smaller
          # osdsPerDevice = "1" # this value can be overridden at the node or device level
          # encryptedDevice = "true" # the default value for this option is "false"
          # Individual nodes and their config can be specified as well, but 'useAllNodes' above must be set to false. Then, only the named
          # nodes below will be used as storage resources.  Each node's 'name' field should match their 'kubernetes.io/hostname' label.
          #    nodes = [
          #      {
          #        name = "172.17.4.201"
          #        devices = { # specific devices to use for storage can be specified for each node
          #          {
          #            name = "sdb"
          #          },
          #          {
          #            name = "nvme01" # multiple osds can be created on high performance devices
          #            config = {
          #              osdsPerDevice = "5"
          #            }
          #          },
          #          {
          #            name = "/dev/disk/by-id/ata-ST4000DM004-XXXX" # devices can be specified using full udev paths
          #          }
          #        },
          #        config = { # configuration can be specified at the node level which overrides the cluster level config
          #        }
          #      },
          #      {
          #        name = "172.17.4.301"
          #        deviceFilter = "^sd."
          #      }
          #    ]
          # The section for configuring management of daemon disruptions during upgrade or fencing.
        }
      }

      resources = {
        #  prepareosd = {
        #    limits = {
        #      cpu    = "200m"
        #      memory = "200Mi"
        #    }
        #    requests = {
        #      cpu    = "200m"
        #      memory = "200Mi"
        #    }
        #  }
        # The above example requests/limits can also be added to the other components
      }

      # The section for configuring management of daemon disruptions during upgrade or fencing.
      disruptionManagement = {
        # If true, the operator will create and manage PodDisruptionBudgets for OSD, Mon, RGW, and MDS daemons. OSD PDBs are managed dynamically
        # via the strategy outlined in the [design](https://github.com/rook/rook/blob/master/design/ceph/ceph-managed-disruptionbudgets.md). The operator will
        # block eviction of OSDs by default and unblock them safely when drains are detected.
        managePodBudgets = true
        # A duration in minutes that determines how long an entire failureDomain like `region/zone/host` will be held in `noout` (in addition to the
        # default DOWN/OUT interval) when it is draining. This is only relevant when  `managePodBudgets` is `true`. The default value is `30` minutes.
        osdMaintenanceTimeout = 30
        # A duration in minutes that the operator will wait for the placement groups to become healthy (active+clean) after a drain was completed and OSDs came back up.
        # Operator will continue with the next drain if the timeout exceeds. It only works if `managePodBudgets` is `true`.
        # No values or 0 means that the operator will wait until the placement groups are healthy before unblocking the next drain.
        pgHealthCheckTimeout = 0
        # If true, the operator will create and manage MachineDisruptionBudgets to ensure OSDs are only fenced when the cluster is healthy.
        # Only available on OpenShift.
        manageMachineDisruptionBudgets = false
        # Namespace in which to watch for the MachineDisruptionBudgets.
        machineDisruptionBudgetNamespace = "openshift-machine-api"
      }
      # security oriented settings
      # security:
      # To enable the KMS configuration properly don't forget to uncomment the Secret at the end of the file
      #   kms:
      #     # name of the config map containing all the kms connection details
      #     connectionDetails:
      #        KMS_PROVIDER: "vault"
      #        VAULT_ADDR: VAULT_ADDR_CHANGE_ME # e,g: https://vault.my-domain.com:8200
      #        VAULT_BACKEND_PATH: "rook"
      #        VAULT_SECRET_ENGINE: "kv"
      #     # name of the secret containing the kms authentication token
      #     tokenSecretName: rook-vault-token
    }
    # healthChecks
    # Valid values for daemons are 'mon', 'osd', 'status'
    healthCheck = {
      daemonHealth = {
        mon = {
          disabled = false
          interval = "45s"
        }
        osd = {
          disabled = false
          interval = "60s"
        }
        status = {
          disabled = false
          interval = "60s"
        }
      }
      # Change pod liveness probe, it works for all mon,mgr,osd daemons
      livenessProbe = {
        mon = {
          disabled = false
        }
        mgr = {
          disabled = false
        }
        osd = {
          disabled = false
        }
      }
    }
  }
}
