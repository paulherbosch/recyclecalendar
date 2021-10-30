# recyclecalendar
Convert recycleapp.be API into ICS calendar

# Info
Met deze webapplicatie kan u een afvalkalender genereren in ICS formaat die in een kalenderapplicatie kan ingeladen worden (google calender, apple ical, ...)  
Op dit moment kunnen enkel kalenders gegenereerd worden voor adressen in Vlaanderen.

Deze applicatie gebruikt <a href="https://recycleapp.be/">https://recycleapp.be/</a> als datasource.  
Recycleapp.be bevat veel meer informatie dan deze applicatie en kan ook informatie verstrekken voor adressen in Brussel en Wallonie.  
Spijtig genoeg ondersteunt recycleapp.be het ical formaat niet meer.  
Een aanvraag voor ical-support werd ingediend bij recyclapp.be  

# Logging
De enige informatie die deze applicatie logt zijn de adressen die ingevoerd worden.  
Dit om eventuele problemen met foutieve zoekopdrachten te kunnen onderzoeken.

# Bugs
Deze applicatie is een hobbyproject en komt zonder enige vorm van garantie of support.  
Bugs en issues mogen steeds gemeld worden op de github pagina van dit project.

# .ENV
see the .env.example file for a list of expected environment variables

# Caching
The app stores a list of pickup events in a database caching table to reduce the number of api calls made to recycleapp.be.  
Each cache entry expires after 14 days by default.

# Issues
recycleapp.be seems to be blocking access to their API for certain ip addresses.  
this app allows you to define a list of (open) proxy servers to access recycleapp.be.  
when mutiple proxies are defined, each proxy will be tested to see if it has access to recycleapp.be.

open proxy performance is flaky and can result in errors from time to time.

# TODO
- ajax-like input fields: fetch address info while user types
- add brussels and wallonia address support
- multi-language
- fetch special events as well, not only pickups
- create proper html calendar layout instead of simple list
