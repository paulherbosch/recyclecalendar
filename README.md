# NOTIFICATION
As of 2021-01-29 this app no longer works.  
Recycleapp.be has locked down access to the api.  

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

# TODO
- ajax-like input fields: fetch address info while user types
- add brussels and wallonia address support
- multi-language
- fetch special events as well, not only pickups
- create proper html calendar layout instead of simple list
