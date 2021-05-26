variable "ceph_cloud_storage_spec" {
  description = "Describe the cloud storage CEPH will use, leave out for local storage"
  type = object({
    storageClassName = string
    resources = object({
      requests = object({
        storage = string
      })
    })
  })
  default = null
  # Cloud example
  # default = {
  #   storageClassName = "standard"
  #   resources = {
  #     requests = {
  #       storage = "100Gi"
  #     }
  #   }
  # }
}
