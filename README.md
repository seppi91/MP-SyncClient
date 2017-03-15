# MP-SyncClient
Share the databases of Mediaportal between multiple instances running at the same time

## Syncronisation tab

http://img202.imageshack.us/img202/9095/syncronisation.jpg

This tab sets up you various sync-setting. The first three boxes let you choose which plugins should get updated, the "configure" button behind these three lines let's you choose which tables should not be touched. Basically all user options will be kept on the client by clicking on the "standard button".

### Program Section

As mentioned already in the SyncServer wiki you have to install the SyncBack tool to update also the ProgramData directories.

### Profile Section

Beneath you have to choose the profiles, which SyncClient starts while synchronizing. You can also click on the "load profiles from syncback" button to get all entered profiles from SyncBack. After that don't forget to check them!

## Resume/Suspend tab

http://img64.imageshack.us/img64/5879/resumesuspend.jpg

Here you can click various events that should be run after Resume or Suspend!

## Paths tab

http://img39.imageshack.us/img39/2739/pathse.jpg

Enter Here all paths to get SyncClient fully working.

## Settings tab

http://img3.imageshack.us/img3/5253/settingsv.jpg

Here you can setup advanced configurations like how the appearance of SyncClient should be set. Or which Exit Mode for the TV-Service should be chosen. "Kill" is just more radical and faster than the generally used "stop service".
