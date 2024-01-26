# snipe-it-collector
Single-script agent to create new Assets in a Snipe-IT database

The API key and base URL for your server need to be in a file called "config.json".

IMPORTANT: if you want to use the script to create an Asset Model before adding the asset, you must fill in the values for asset_manufacturer_id and asset_category_id that match the ID of the defaults you want to use.

For example, you would create a new manufacturer under Settings -> Manufacturers, make a note of the ID of the new record and fill in that value here.  The same can be done for category (Settings -> Categories).

The Field Set is optional and can be used to create the asset model with a custom field (Settings -> Custom Fields).

```json
{
    "apiKey": "YOUR_KEY_HERE",
    "baseUrl": "https://yourserver.example.com",
    "asset_manufacturer_id": 0,
    "asset_eol": 72,
    "asset_fieldset_id": 0,
    "asset_category_id": 0
}
```

To make it easier to deploy to remote machines, I created a makefile that packages the script and JSON file together in an encrypted ZIP file.  You will need to create a file called ```deploy.txt``` with the destination path for the ZIP file.  I set it to a location in Dropbox.  For example:

```
/home/username/Dropbox/deploy
```

If you do not have a ```deploy.txt``` file and run the makefile, it will attempt to create the file in your root folder (Linux) and that is probably not what you want.

# References

 * https://snipe-it.readme.io/reference
 * https://github.com/snazy2000/SnipeitPS
 * https://www.reddit.com/r/sysadmin/comments/bf3web/snipe_it_powershell_automation/
