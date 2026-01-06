{
  config,
  pkgs,
  lib,
  eso,
  hlib,
  ...
}:
{
  config = lib.mkIf (config.stage == "full") {
    # \\u531666-sub1.your-storagebox.de\u531666-sub1
    csi-driver-smb.enable = true;
    kubernetes.resources.kube-system.ExternalSecret.sb1-kube = hlib.eso.mkBasic "name:hcloud-sb1-kube";
  };
}
