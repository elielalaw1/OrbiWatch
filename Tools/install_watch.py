import argparse
import asyncio
import plistlib
import struct
import zlib
from pathlib import Path
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.service_connection import ServiceConnection
from pymobiledevice3.services.installation_proxy import InstallationProxyService

EXTRA = bytes.fromhex('55540d0007f3a2ec60f6a2ec60f3a2ec6075780b000104f50100000414000000')

async def send_entry(connection, name, data=b''):
    name = name.encode('utf-8')
    header = struct.pack('<IHHHHHIIIHH', 0x04034b50, 20, 0, 0, 0xbdef, 0x52ec,
                         zlib.crc32(data) & 0xffffffff, len(data), len(data), len(name), len(EXTRA))
    await connection.sendall(header + name + EXTRA + data)

async def main(phone_id, watch_id, app_path):
    with (app_path / "Info.plist").open("rb") as info:
        bundle_id = plistlib.load(info)["CFBundleIdentifier"]
    phone = await create_using_usbmux(serial=phone_id)
    controls = []
    async def forward(port, service_name=None):
        control = await phone.start_lockdown_service('com.apple.companion_proxy')
        controls.append(control)
        request = {'Command':'StartForwardingServicePort', 'GizmoRemotePortNumber':port,
                   'IsServiceLowPriority':False, 'PreferWifi':False}
        if service_name:
            request['ForwardedServiceName'] = service_name
        response = await control.send_recv_plist(request)
        if not response.get('CompanionProxyServicePort'):
            raise RuntimeError(str(response))
        return response['CompanionProxyServicePort']
    watch = await create_using_usbmux(serial=phone_id, identifier=watch_id,
        port=await forward(62078, 'com.apple.mobile.lockdownd'), autopair=False)
    if not watch.paired:
        raise RuntimeError('Existing Watch trust could not be validated')
    async def connect(port, ssl_context=None, strip_ssl=False):
        return await ServiceConnection.create_using_usbmux(phone_id, await forward(port),
            ssl_context=ssl_context, strip_ssl=strip_ssl)
    watch.create_service_connection = connect
    try:
        if not await watch.get_developer_mode_status():
            raise RuntimeError('Watch Developer Mode is not enabled')
        files = sorted(p for p in app_path.rglob('*') if p.is_file())
        total = sum(p.stat().st_size for p in files)
        print(f'Streaming signed Orbi: {len(files)} files, {total} bytes', flush=True)
        async with await watch.start_lockdown_service('com.apple.streaming_zip_conduit') as connection:
            await connection.send_plist({
                'InstallOptionsDictionary': {'DisableDeltaTransfer':1,
                    'InstallDeltaTypeKey':'InstallDeltaTypeSparseIPAFiles',
                    'IsUserInitiated':1, 'PackageType':'Customer', 'PreferWifi':1},
                'InstallTransferredDirectory':1,
                'MediaSubdir':'PublicStaging/Orbi.app.ipa', 'UserInitiatedTransfer':0})
            metadata = {'StandardDirectoryPerms':16877, 'StandardFilePerms':-32348,
                        'RecordCount':len(files)+2, 'TotalUncompressedBytes':total, 'Version':2}
            await send_entry(connection, 'META-INF/')
            await send_entry(connection, 'META-INF/com.apple.ZipMetadata.plist',
                             plistlib.dumps(metadata, fmt=plistlib.FMT_XML))
            for p in files:
                await send_entry(connection, 'Payload/Orbi.app/' + p.relative_to(app_path).as_posix(), p.read_bytes())
            await connection.sendall(b'PK\x01\x02')
            while True:
                response = await connection.recv_plist()
                if response.get('Status') == 'DataComplete':
                    print('WATCH INSTALLATION COMPLETE', flush=True)
                    break
                progress = response.get('InstallProgressDict', {})
                if progress.get('Error'):
                    raise RuntimeError(f"{progress['Error']}: {progress.get('ErrorDescription')}")
                print('Watch:', progress.get('PercentComplete'), progress.get('Status'), flush=True)
        async with InstallationProxyService(watch) as installer:
            apps = await installer.get_apps(bundle_identifiers=[bundle_id])
            app = apps.get(bundle_id)
            if not app:
                raise RuntimeError('Orbi not found in installed app lookup after transfer')
            print('VERIFIED INSTALLED:', {k:app.get(k) for k in ['CFBundleIdentifier','CFBundleVersion','ApplicationType','Path']}, flush=True)
    finally:
        await watch.close()
        for control in controls:
            await control.close()
        await phone.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Install a signed Orbi.app on an already paired development watch via its iPhone.")
    parser.add_argument("--phone", required=True, help="Paired iPhone UDID")
    parser.add_argument("--watch", required=True, help="Apple Watch UDID")
    parser.add_argument("--app", required=True, type=Path, help="Path to signed watchOS Orbi.app")
    args = parser.parse_args()
    asyncio.run(asyncio.wait_for(main(args.phone, args.watch, args.app), 180))
