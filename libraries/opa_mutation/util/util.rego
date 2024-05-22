package global.opa_mutation.util
  
import future.keywords.in

default opa_image := "openpolicyagent/opa:latest-envoy-rootless" 

opa_image := data.policy["com.styra.kubernetes.mutating"].rules.rules.rapid_channel_opa_image {
  data.library.parameters.channel == "Rapid"
}

opa_image := data.policy["com.styra.kubernetes.mutating"].rules.rules.regular_channel_opa_image {
  data.library.parameters.channel == "Regular"
}

opa_image := data.policy["com.styra.kubernetes.mutating"].rules.rules.stable_channel_opa_image {
  data.library.parameters.channel == "Stable"
}

injectable_object {
  injectable_pod
}
  
injectable_pod {
  input.request.kind.kind == "Pod"
  not input.request.namespace == "kube-system"
  not input.request.object.metadata.labels.app == "slp"
  input.request.operation in ["CREATE", "UPDATE"]
}

injection_enabled_ns {
  data.kubernetes.resources.namespaces[input.request.namespace].metadata.labels[data.library.parameters.label] == data.library.parameters["label-value"]
}

injection_disabled_ns {
  data.kubernetes.resources.namespaces[input.request.namespace].metadata.labels[data.library.parameters.label] != data.library.parameters["label-value"]
}

injection_unlabeled_ns {
  not data.kubernetes.resources.namespaces[input.request.namespace].metadata.labels[data.library.parameters.label]
}

injection_enabled_pod {
   input.request.object.metadata.labels[data.library.parameters.label] == data.library.parameters["label-value"]
}

injection_disabled_pod {
  input.request.object.metadata.labels[data.library.parameters.label] != data.library.parameters["label-value"]
}

injection_unlabeled_pod {
  not input.request.object.metadata.labels[data.library.parameters.label]
}

opa_container_exists {
  input.request.object.spec.containers[_].name == "opa"
}

opa_container_exists {
  input.request.object.spec.template.spec.containers[_].name == "opa"
}

add_operation {
  injection_enabled_pod
  not opa_container_exists
}

add_operation {
  injection_unlabeled_pod
  injection_enabled_ns
  not opa_container_exists
}

remove_operation {
  injection_disabled_pod
  opa_container_exists
}

remove_operation {
  injection_unlabeled_pod
  not injection_enabled_ns
  opa_container_exists
}

root_path := "" {
  injectable_pod
}

opa_config_mount := {
	"readOnly": true,
	"mountPath": "/config",
	"name": "opa-config-vol",
}

opa_socket_mount := {
	"readOnly": false,
	"mountPath": "/run/opa/sockets",
	"name": "opa-socket",
}
    
opa_volume_mounts := [opa_config_mount] {
  not data.library.parameters["use-socket"] == "Yes"
}
opa_volume_mounts := [opa_config_mount, opa_socket_mount] {
  data.library.parameters["use-socket"] == "Yes"
}

opa_patch := patch {
  add_operation
  patch := {
        "op": "add",
        "path": sprintf("%v/spec/containers/-",[root_path]),
        "value": {
          "name": "opa",
          "image": opa_image,
          "securityContext": {
            "runAsUser": 1111
          },
          "volumeMounts": opa_volume_mounts,
          "env": [
            {
              "name": "OPA_LOG_TIMESTAMP_FORMAT",
              "value": "2006-01-02T15:04:05.999999999Z07:00"
            }
          ],
          "args": [
            "run",
            "--server",
            "--config-file=/config/conf.yaml",
            "--addr=http://127.0.0.1:8181",
            "--diagnostic-addr=0.0.0.0:8282",
            "--authorization=basic"
          ],
          "readinessProbe": {
            "initialDelaySeconds": 20,
            "httpGet": {
              "path": "/health?plugins",
              "scheme": "HTTP",
              "port": 8282
            }
          },
          "resources": {
            "requests": null,
            "limits": null
          }
        }
    }
  }

opa_patch := patch {
  remove_operation
  
  some i
  input.request.object.spec.containers[i].name == "opa"
  
  patch := {
        "op": "remove",
        "path": sprintf("%v/spec/containers/%v",[root_path, i])
       }
}

existing_volumes {
  input.request.object.spec.template.spec.volumes
}
existing_volumes {
  input.request.object.spec.volumes
}

opa_volume_patch := patch {
  add_operation
  existing_volumes
  patch := {
        "op": "add",
        "path": sprintf("%v/spec/volumes/-", [root_path]),
        "value": opa_volume
      }
}
opa_volume_patch := patch {
  add_operation
  not existing_volumes
  patch := {
    "op": "add",
    "path": sprintf("%v/spec/volumes", [root_path]),
    "value": [opa_volume]
  }
}

opa_volume_patch := patch {
  remove_operation
  existing_volumes
  
  some i
  input.request.object.spec.volumes[i].name == "opa-config-vol"
  
  patch := {
    "op": "remove",
    "path": sprintf("%v/spec/volumes/%v", [root_path, i])
  }
}

opa_volume := {
  "name": "opa-config-vol",
  "configMap": {
    "name": data.library.parameters.config
  }
}
