# mediawiki-confluence-upload

This script can assist in the conversion and upload of MediaWiki markup/attachments to Atlassian
Confluence Cloud. I used this to migrate a MediaWiki 1.28.2/MySQL wiki to Confluence Cloud.

*Status: Mostly working - small issues with attachment processing*

It's licensed under the Apache License 2.0, see LICENSE.txt. It's provided as-is - if it helps you,
that's great! If it doesn't, well, you have the source :)

It is not a complete solution - it requires the use of the deprecated Universal Wiki Converter in
the first two stages of the conversion:
1) as a first stage to export the MediaWiki pages to files on disk
2) as a second stage to convert these MediaWiki markup pages to Confluence markup format.

UWC is an excellent converter and this task would be massively more involved without it, however
there are two problems to overcome, that this script helps with:
1) UWC's conversion to Confluence markup is incomplete: there are some markup elements that are 
   not converted to the correct Confluence Cloud format. The UWC was deprecated, possibly before
   Confluence Cloud was introduced; it looks like UWC converts to an older markup format.
2) UWC does not connect correctly to Confluence Cloud - after setting up the correct keystore file
   that would permit HTTPS access to Confluence Cloud, and given an account with the correct
   permissions, and the key of a space that exists, and with the XML-RPC API enabled, UWC would not
   connect correctly: "BAD_SPACE or USER_NOT_PERMITTED Either the space does not exist, or the user
   has no access to that space." - neither of which were correct. The UWC log contains "Fatal error 
   parsing XML: org.xml.sax.SAXParseException; lineNumber: 1; columnNumber: 707; attribute name not
   followed by '=' - Caused by org.apache.xmlrpc.XmlRpcClientException: Failure writing request"

Given these failures, this script was written to:
1) Finish the conversion of Confluence markup to modern Confluence Cloud markup.
2) Use the Confluence Cloud REST API to convert this to Confluence's XHTML-based storage
   format, since it no longer stores pages in markup format.
3) Use the REST API to upload the storage-format page and any referenced attachments to a named 
   space.

# Prerequisites
You'll need:
* A reasonably modern Linux/macOS/UNIX system. You may be able to do this on Windows, good luck.
* Perl 5 (any modern sub-version will do) and the packages:
  * LWP::UserAgent
  * HTTP::Request::Common
  * JSON
  * HTML::Entities
  * Text::CSV
* The UWC, cloned and built locally. You'll need Java 6 for that.
* Access details for your MediaWiki database (database name, hostname, database prefix, database
  login and password). These should be available from your LocalSettings.php. e.g. in 
  `/var/www/mediawiki/LocalSettings.php`. 
* Disk space for holding exported MediaWiki pages.
* An archive of your MediaWiki attachments / images (static resources). This would be an archive
  of the `$wgResourceBasePath` that contains the 'images' folder. It contains a couple of levels of
  numbered directories, that spread uploaded images across the filesystem for faster access. The
  upload script here will scan through that tree to find your resources. 

# Stage One: Building the Universal Wiki Creator
Documentation for UWC is no longer online; it is available from the Internet Archive at:
http://web.archive.org/web/20170325014930/https://migrations.atlassian.net/wiki/display/UWC/Universal+Wiki+Converter

The source to UWC is still hosted in a BitBucket git repository. You will need to clone the UWC from
https://bitbucket.org/appfusions/universal-wiki-converter/src/master/

This is a Java 6 project; it does not build on Java 8 (have not tried anything more modern).
I used an older CentOS 7.9 system with OpenJDK 6, git, and Apache Ant installed.

Clone the UWC repo, and build by running 'ant'. This will give you a directory called `uwc` in the 
`target` directory. (I archived this, and copied it across to a more modern system to run it.)

# Stage Two: Exporting your MediaWiki data using UWC
In your built `uwc` directory, there's a script `run_uwc_devel.sh` which you'll use to run UWC. Before
you do, edit the `conf/exporter.mediawiki.properties` file, and supply these (filling in the values
from your MediaWiki's `LocalSettings.php`):
* `databaseName=mediawikidb`
* `dbUrl=jdbc:mysql://my-wiki-hostname.my-company.net:3306`
* `login=mediawiki_database_user`
* `password=secret_words_go_here`
* `output=/Users/bob/uwc/` (UWC will export files to an `exported_mediawiki_pages` dir under here)
* `dbPrefix=wiki`

Extract the archive of your MediaWiki static resources into a directory (for this example, I'll use
`/Users/bob/mediawiki-images`).

Run `./run_uwc_devel.sh`. 

On the 'Conversion Settings' tab, choose 'mediawiki' as the Type; for the Attachments, browse to
`/Users/bob/mediawiki-images`.

On the 'Other Tools' tab, uncheck "Pages will be sent to Confluence at the end of the conversion, if
this is checked."

Click 'Export', and UWC should export all your MediaWiki markup to the directory
`/Users/bob/uwc/exported_mediawiki_pages`. This may take some time. When done, close UWC.

# Stage Three: Convert the MediaWiki markup pages to Confluence markup pages using UWC
UWC needs a couple of changes to its default configuration. 
Change the `conf/converter.mediawiki.properties` file with the following changes and additions:
Disable the XmlConverter (which will otherwise fail the conversion) by commenting a line out, and
ensure the converter saves the Confluence markup to disk by adding a line at the end of the file - like this:
```
#Mediawiki.1690.xmlconverter.class=com.atlassian.uwc.converters.xml.XmlConverter
...
Mediawiki.9999.engine-saves-to-disk.property=true
```

Run UWC, and click 'Add' to choose the pages to convert. Browse to your `/Users/bob/uwc/exported_mediawiki_pages`
directory, and choose some or all pages (shift-select multiple files). Then click 'Choose'. The list
of Pages should fill up.

*Ensure that on the 'Other Tools' tab, 'Pages will be sent to Confluence...' is UNCHECKED.* 

Click 'Convert'. This will take some time. When done, the converted Confluence markup will be stored
in the `/Users/bob/uwc/output/output` directory

# Stage Four: Convert the Confluence markup pages to Confluence storage format and upload
The `upload.pl` script you'll find in this project requires a configuration file. See the file
`sample.configuration.properties` for an example (that follows the directories given in here.)

Rename this to `configuration.properties` and supply your own values for what you find there.

You will need an Atlassian API token in order to use the Confluence Cloud REST API.
For information on how to create an Atlassian API token, please see
https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/

Find a page you want to migrate in your `/Users/bob/uwc/output/output` directory. These page files
will have spaces in them, for example `Project Calypso`. Suppose that this page contains an embedded image,
`[frameless|941x941px|File__Project Calypso Dataflow v2.png]`.

Two things have to happen here:
1) This markup is MediaWiki markup that didn't get converted fully to Confluence markup. There are
   a number of small repairs to make. As a rough conversion the reference to the embedded image
   should be `!Project Calypso Dataflow v2.png!`.
3) The actual image needs finding in the `/Users/bob/mediawiki-images` tree. There are two candidates
   `9/98/Project_Calypso_Dataflow_v2.png` and `thumb/9/98/Project_Calypso_Dataflow_v2.png/941px-Project_Calypso_Dataflow_v2.png`
   and note that the name in the markup contains spaces, but the files have underlines instead. For
   simplicity, the uploader chooses the former of these. 

*The search for the correct attachment is not currently working properly.*

Run the script on this page, to fix the markup, convert it to storage format, and upload to Confluence Cloud:

`perl upload.pl 'Project Calypso'`

Arguments to the script are the names of page files. Since these filenames probably contain spaces,
they'll need quoting or escaping.
