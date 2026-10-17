# Add a machine and its services

Every machine in the library is a host with one or more services. You create and change both in one sheet, with a tab for each kind of service: **Terminal**, **Database** and **Desktop**. This page covers adding a host, adding and editing services, and removing them.

## Add a host

1. Open the sheet in one of these ways:
   - Choose **Add Host** (+). **On Vision Pro:** it is in the bar below the library window.
   - Right-click the empty space in the host list, or touch and hold it (pinch and hold on Vision Pro), and choose **Add Host**.
   - **On Mac:** with the library window in front, choose **File** ▸ **New Host** (⌘N).
2. Under **Machine**, enter a **Name**, such as `alpha`, and an **Address**: a hostname such as `alpha.example.com` or an IP address such as `192.0.2.10`. Do not include a user name, a port or spaces; those belong to the service.
3. Under **Services**, choose **Terminal**, **Database** or **Desktop**. The tab you choose is the service that is added. One sheet adds one service.
4. Fill in the fields for that service. Open **Advanced** for the less common settings. The help for each kind of service describes its fields.
5. Optionally, open **Also known as & Collections** to add other names and collections. See "Favorites, collections and other names".
6. Choose **Add**. **On Mac:** Return also saves.

If a field is missing or invalid, a red message appears under it and the sheet stays open. If the service cannot be saved, nothing is saved: the host is not left behind without it.

> [!IMPORTANT]
> Hosts with the same name are shown as one host. Case does not matter, and `alpha.local` matches `alpha`. Hosts that share an address, or share a name in **Also known as**, are combined too. Give each machine its own name.

## Add another service to a host

1. Select the host.
2. Under **Services**, choose **Add a service…**.
3. The sheet opens on the first kind of service it can add, and is titled after it, for example **Add Terminal to alpha**. Choose a different tab if you want another kind.
4. Fill in the fields and choose **Add**.

If the host has no address yet, the sheet asks for one. The address is saved on the host and shared by all its services.

## Edit a service

1. Select the host.
2. Choose **Edit** (pencil) beside the service.
3. Change the fields in the sheet, titled for example **Edit Terminal on alpha**, and choose **Save**.

## Edit a host

1. Select the host and choose **Edit** at the bottom of its details. You can also right-click the host, or touch and hold it, and choose **Edit**.
2. In **Edit Host**, change the **Name**, **Address**, **Also known as** or **Collections**.
3. Choose **Save**.

Services are not changed from this sheet. Use the buttons beside each service instead.

## Remove a service

1. Select the host.
2. Right-click the service, or touch and hold it (pinch and hold on Vision Pro).
3. Choose **Remove Service**. It takes effect at once, without asking first.

The service's saved settings and saved password are deleted. Built-in services on this device cannot be removed.

## Delete a host

1. Right-click the host, or touch and hold it, and choose **Delete**. You can also choose **Delete Host…** at the bottom of **Edit Host**.
2. Confirm with **Delete**.

> [!WARNING]
> Deleting a host also deletes the saved settings and saved passwords of all its services, on every device that shares your library. It cannot be undone. Keys in **SSH Keys** are not deleted. A device that still has the host when the deletion reaches it can bring the host back; see [When two devices disagree](library-sync.md#when-two-devices-disagree).

The host for this device cannot be deleted.
