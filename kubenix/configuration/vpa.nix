{ config, lib, ... }:
{
  config =
    let
      mkVPA = name: type: {
        ${name} = {
          spec = {
            targetRef = {
              apiVersion = "v1";
              kind = type;
              name = name;
            };
            updatePolicy.updateMode = "InPlaceOrRecreate";
          };
        };
      };
    in
    lib.mkIf (config.stage == "full") {
      vertical-pod-autoscaler = {
        enable = true;
        version = "*";
        helmValues = {
          admissionController.certManager.enabled = config.cert-manager.enable;
          updater.extraArgs = [
            "--min-replicas=1"
            "--eviction-tolerance=1.0"
            # "--in-place-skip-disruption-budget"
            "--in-recommendation-bounds-eviction-lifetime-threshold=3h"
          ];
          recommender.extraArgs = [
            "--pod-recommendation-min-memory-mb=20"
            "--pod-recommendation-min-cpu-millicores=25"
          ];
        };
      };
      kubernetes.resources.caph-system.VerticalPodAutoscaler = mkVPA "caph-controller-manager" "Deployment";
      kubernetes.resources.capi-kubeadm-bootstrap-system.VerticalPodAutoscaler = mkVPA "capi-kubeadm-bootstrap-controller-manager" "Deployment";
      kubernetes.resources.capi-kubeadm-control-plane-system.VerticalPodAutoscaler = mkVPA "capi-kubeadm-control-plane-controller-manager" "Deployment";
      kubernetes.resources.capi-system.VerticalPodAutoscaler = mkVPA "capi-controller-manager" "Deployment";
      kubernetes.resources.flux-system.VerticalPodAutoscaler = lib.mkMerge [
        (mkVPA "helm-controller" "Deployment")
        (mkVPA "kustomize-controller" "Deployment")
        (mkVPA "notification-controller" "Deployment")
        (mkVPA "source-controller" "Deployment")
      ];

      kubernetes.generators = [
        # Deploy VPA objects for all long-lived resource types
        (
          resource:
          lib.optionalAttrs
            (
              (lib.elem resource.kind [
                "Deployment"
                "StatefulSet"
                "DaemonSet"
              ])
              # Allow disabling generated VPA by setting annotations.genvpa to not "true"
              && resource.metadata.annotations."vpa/generate" or "true" == "true"
              # Also check that there isn't already a VPA with the same name configured
              && !lib.hasAttrByPath [
                resource.metadata.namespace
                "VerticalPodAutoscaler"
                resource.metadata.name
              ] config.kubernetes.resources
            )
            {
              apiVersion = "autoscaling.k8s.io/v1";
              kind = "VerticalPodAutoscaler";
              metadata = { inherit (resource.metadata) name namespace; };
              spec = {
                targetRef = {
                  inherit (resource) apiVersion kind;
                  inherit (resource.metadata) name;
                };
                updatePolicy.updateMode = "InPlaceOrRecreate";
              };
            }
        )
      ];
    };
}
