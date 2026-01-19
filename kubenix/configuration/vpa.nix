{ config, lib, ... }:
{
  config = {
    kubernetes.generators = [
      # Deploy VPA objects for all long-lived resource types
      (
        resource:
        lib.optionals
          (
            (lib.elem resource.kind [
              "Deployment"
              "StatefulSet"
              "DaemonSet"
            ])
            # Allow disabling generated VPA by setting annotations.genvpa to not "true"
            && resource.metadata.annotations.genvpa or "true" == "true"
            # Also check that there isn't already a VPA with the same name configured
            && !lib.hasAttrByPath [
              resource.metadata.namespace
              "VerticalPodAutoscaler"
              resource.metadata.name
            ] config.kubernetes.resources
          )
          [
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
          ]
      )
    ];
  };
}
