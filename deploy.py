#! /usr/bin/env python3
import kr8s
import subprocess
import sys
import ipaddress
import time

# Configuration
SSH_USER = "hetzkube"
ATTR_NAME = "nixosConfigurations.image-x86_64-linux"


def get_ipv4_external_ip(node):
    if not hasattr(node.status, "addresses"):
        return None
    for addr in node.status.addresses:
        if addr.type == "ExternalIP":
            try:
                if ipaddress.ip_address(addr.address).version == 4:
                    return addr.address
            except ValueError:
                continue
    return None


def wait_for_ssh(target, timeout=300):
    """Polls SSH until connection succeeds."""
    print(f"Waiting for {target} to come online...", end="", flush=True)
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            # -o ConnectTimeout=2 speeds up the failure loop
            subprocess.run(
                ["ssh", "-o", "ConnectTimeout=2", target, "exit 0"],
                check=True,
                capture_output=True,
            )
            print(" Online!")
            return True
        except subprocess.CalledProcessError:
            time.sleep(2)
            print(".", end="", flush=True)
    print(" Timed out.")
    return False


def main():
    # 1. Capture source path
    nix_expr = '(builtins.fetchTree { type = "git"; url = ./.;}).outPath'
    try:
        src_path = subprocess.check_output(
            ["nix", "eval", "--impure", "--raw", "--expr", nix_expr], text=True
        ).strip()
    except subprocess.CalledProcessError as e:
        sys.exit(f"Nix eval failed: {e}")

    print(f"Source path: {src_path}")

    try:
        nodes = kr8s.get("nodes")
    except Exception as e:
        sys.exit(f"Kubernetes API error: {e}")

    for node in nodes:
        name = node.metadata.name
        ip = get_ipv4_external_ip(node)

        if not ip:
            print(f"Skipping {name}: No IPv4 ExternalIP found")
            continue

        target = f"{SSH_USER}@{ip}"
        print(f"--> Processing {name} ({target})")

        try:
            # 1. Drain
            print(f"Draining {name}...")
            subprocess.run(
                [
                    "kubectl",
                    "drain",
                    name,
                    "--delete-emptydir-data",
                    "--ignore-daemonsets",
                    "--force",  # Needed if pods are not managed by controller
                ],
                check=True,
            )

            # 2. Deploy
            subprocess.run(
                ["ssh-keygen", "-R", ip], check=True, stderr=subprocess.DEVNULL
            )
            subprocess.run(
                ["nix", "copy", "--to", f"ssh-ng://{target}", src_path], check=True
            )

            subprocess.run(
                ["ssh-keygen", "-R", ip], check=True, stderr=subprocess.DEVNULL
            )
            subprocess.run(
                [
                    "ssh",
                    target,
                    "--",
                    f"nixos-rebuild switch --sudo --file {src_path} --attr {ATTR_NAME}",
                ],
                check=True,
            )

            # 3. Cleanup & Reboot
            subprocess.run(
                ["ssh-keygen", "-R", ip], check=True, stderr=subprocess.DEVNULL
            )
            subprocess.run(["ssh", target, "--", "nix-collect-garbage -d"], check=True)

            print("Rebooting...")
            try:
                # Reboot usually causes SSH to exit 255 (connection closed)
                subprocess.run(
                    ["ssh", target, "--", "sudo systemctl reboot"], check=True
                )
            except subprocess.CalledProcessError:
                pass  # Expected behavior on reboot

            # 4. Wait for Recovery
            # Sleep briefly to ensure the node actually goes down before we start polling
            time.sleep(10)
            subprocess.run(
                ["ssh-keygen", "-R", ip], check=True, stderr=subprocess.DEVNULL
            )

            if not wait_for_ssh(target):
                print(f"CRITICAL: Node {name} failed to come back online. Stopping.")
                sys.exit(1)

            # 5. Uncordon
            print(f"Uncordoning {name}...")
            subprocess.run(["kubectl", "uncordon", name], check=True)

        except subprocess.CalledProcessError as e:
            print(f"Failed during operations on {name}: {e}", file=sys.stderr)
            # Decide if you want to exit or continue to next node
            # sys.exit(1)


if __name__ == "__main__":
    main()
