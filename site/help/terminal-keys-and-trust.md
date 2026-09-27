# Sign in with keys and trust host keys

This page covers the two kinds of key SSH uses: your own key, which proves who you are to a machine, and the machine's host key, which proves the machine is the one you meant to reach.

## Sign in with an SSH key

Your keys are kept in the library's **SSH Keys**, where you import, generate, rename and delete them. See [Manage SSH keys](library-ssh-keys.md) for that list.

To make a Terminal service sign in with a key:

1. Edit the host's Terminal service.
2. Set **Method** to **SSH Key**.
3. Pick the key in **SSH Key**. To import one on the spot, choose **Add SSH Key**; the new key is selected for you.
4. Save the sheet.

An imported key must be an RSA or ED25519 key in OpenSSH format: a file that begins `-----BEGIN OPENSSH PRIVATE KEY-----`. If the key has a passphrase, **Add SSH Key** asks for it once and keeps it with the key.

A key made with **Generate in the Secure Enclave…** is an ECDSA P-256 key that never leaves the device, and each use asks you to confirm that you are present.

> [!IMPORTANT]
> A Secure Enclave key is marked **This device only**. A Terminal service that uses it works only on that device and does not appear on your other devices. Choose an imported key for a service you want everywhere.

## Put your public key on a server

1. In **SSH Keys**, select the key.
2. Choose **Copy Public Key**, or **Export…** to save it as a file.
3. Add it to the account's `~/.ssh/authorized_keys` on the server, for example for `ann`.

## Trust a machine's host key

The first time you connect to a machine, **Trust SSH Host Key?** shows the key's algorithm and SHA-256 fingerprint.

1. Compare the fingerprint with the one the machine reports. On the machine, `ssh-keygen -lf` on its host key file prints it.
2. Choose **Trust and Connect** if they match, or **Cancel** if they do not.

The app remembers the key for that address and port. Anything else in the app that reaches the machine over SSH, such as a database tunnel, uses the same trust, so you are not asked again.

## When a host key changes

If the machine presents a different key from the one you trusted, **SSH Host Key Changed** appears with the new algorithm and fingerprint.

A key changes legitimately when a server is rebuilt or reinstalled. It also changes when something is intercepting the connection.

- If you know why the key changed and the new fingerprint is right, choose **Trust Changed Key**. The new key replaces the old one.
- Otherwise, choose **Cancel** and find out why before you connect.

> [!WARNING]
> Do not choose **Trust Changed Key** just to make the message go away. It is the one warning that tells you the machine may not be the one you meant to reach.

## Refuse unknown keys

To never be asked, and instead refuse any key you have not already trusted:

1. Open Settings, then **Connections**.
2. Under **Security**, set **Host key verification** to **Strict**.

In **Strict** mode, a new or changed key stops the connection and says why. No trust decision is recorded. **Ask** is the default.
