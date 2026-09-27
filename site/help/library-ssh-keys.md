# Manage SSH keys

**SSH Keys** keeps every key you can sign in with, in one place. A key can sign in to any number of machines and stays here when a service that uses it is deleted. This page covers importing and generating keys, reading a key's details, and copying, renaming and deleting keys.

## Open SSH Keys

- **On Vision Pro:** choose the **SSH Keys** tab beside the library window.
- **On Mac, iPad and iPhone:** choose **SSH Keys** in the sidebar's **Keys** section. The number beside it is how many keys you have.

Use **Search Keys** to filter the list by name.

## Import a key

1. Choose **Add Key** (+), then **Import a Key…**. If you have no keys yet, you can also choose **Import a Key…** in the empty list.
2. In **Add SSH Key**, enter a **Key name**.
3. Choose **Choose File…** and pick the private key file, or paste the key's contents into the text area. **On Mac:** the file panel opens in your `.ssh` folder and shows hidden files.
4. The sheet shows what it found, such as the key type and whether a passphrase is required. If it is, enter the **Passphrase**.
5. Choose **Save**.

RSA and ED25519 private keys are supported. When you choose a file and have not typed a name, the name is filled in from the key's comment or the file name.

## Generate a key in the Secure Enclave

1. Choose **Add Key** (+), then **Generate in the Secure Enclave…**.
2. In **Generate Key**, enter a **Key name**.
3. Choose **Generate**.

This creates an ECDSA P-256 key inside this device's Secure Enclave. The private key never leaves it, and each use requires you to confirm that you are present, with biometrics or your device passcode or password.

> [!IMPORTANT]
> A Secure Enclave key works only on the device that generated it. It is marked **This device only**, and services that use it do not appear on your other devices. If this device has no Secure Enclave, generating a key fails with an error.

## Read a key's details

Select a key to see:

- **Key**: the **Algorithm** (such as ED25519 or P-256), the **Storage** (**Imported** or **Secure Enclave**), the **Fingerprint** and the date it was **Added**. The fingerprint begins `SHA256:` and can be selected and copied, so you can compare it with what a server reports.
- **Availability**: **iCloud** if the key is available on every device signed in to your iCloud account, or **This device only** for a Secure Enclave key.
- **Used By**: every service that signs in with this key, with the host it is on. If a service's settings were saved by a newer version of the app, a warning says how many services could not be read and may also use the key.

Each row shows the key's storage and algorithm, such as **Imported ED25519**, and where it is available. A number at the end of the row shows how many services use it.

## Share the public key

To put the key on a server, you need its public half.

- Choose **Copy Public Key** to copy it to the clipboard.
- Choose **Export…** to save it as a text file. The file name is the key's name ending in `.pub`.

**Copy Public Key** is also in the key's menu: right-click the key, or touch and hold it.

## Rename or delete a key

- To rename, choose **Rename**, enter the new **Key name** in **Rename SSH Key**, and choose **Save**.
- To delete, choose **Delete**. The confirmation names the services that will be left without a key. Choose **Delete** followed by the key's name to confirm.

> [!WARNING]
> Deleting a key removes it from secure storage and cannot be undone. Services that used it can no longer sign in with it until you choose another key.
