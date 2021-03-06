## Running this code takes an Excel file in your directory for a raw, unedited match actions 
## spreadsheet and turns it into a data.frame that can be read by the creating-stats.R code
##
##
## Install if necessary
require(readxl)
require(xlsx)
require(RCurl)

##0. REFERENCE DATA TO SOURCE----------
### ref.classes will be a data.frame of class data for columns in the spreadsheet.
### Sourcing this data.frame and creating the col_types vector below will be
### necessary due to how read_excel() requires the column class types to be in a
### vector for every column in the spreadsheet in the precise order in which they appear.
ref.classes <- getURL("https://raw.githubusercontent.com/amj2012/wosostats/master/resources/spreadsheet-classes.csv")
ref.classes <- read.csv(textConnection(ref.classes), stringsAsFactors = FALSE)
working.names <- colnames(read_excel(match))
#needs to return a col_types character that has ALL column classes for EXACTLY 
#every column in the excel spreadsheet
col_types <- character(length(working.names))
x <- 1
while (x <= length(working.names)){
  #checks if the column name at working.names[x] is a column name with a preassigned class type
  if(working.names[x] %in% ref.classes$col.name) {
    #if TRUE, then gets the column's preassigned class type, and assigns that as an element in col_type
    if(ref.classes[ref.classes[,"col.name"]==working.names[x],"col.class"] == "numeric" | 
       ref.classes[ref.classes[,"col.name"]==working.names[x],"col.class"] == "integer") {
      col_types[x] <- "numeric"
    } else if (ref.classes[ref.classes[,"col.name"]==working.names[x],"col.class"] == "character") {
      col_types[x] <- "text"
    } else {
      col_types[x] <- "blank"
    }
  } else {
   col_types[x] <- "blank" 
  }
  x <- x + 1
}
rm(x)
rm(working.names)
###
### rosters is a data.frame of player data. For now this is just 2016 NWSL player
### data. This is to account for multiple teams with players with the same last name,
### among other pesky scenarios
rosters <- getURL("https://raw.githubusercontent.com/amj2012/wosostats/master/rosters/nwsl-2016.csv")
rosters <- read.csv(textConnection(rosters), stringsAsFactors = FALSE)

##1. READING THE EXCEL FILE----------
## "match" must be a string value and the Excel file must be in the working directory
df <- read_excel(match, col_types = col_types)
df <- as.data.frame(df)
rm(col_types, ref.classes)

##2. CHANGE COLUMN CLASSES----------
## Changes class of select columns if necessary
## Since this code moved on to using the readxl package instead of the
## xlsx package, changing the column classes isn't necessary.

##3. DELETE EXCESS COLUMNS AND ROWS----------
## Gets rid of NA columns
df <- df[,!grepl("^NA",names(df))]
## Gets rid of any blank rows after the match has ended (indicated by an end.of.match value)
df <- df[1:max(grep("end.of.match", df[,"poss.action"])),]

##4. ADD COMMON MISSING COLUMNS----------
### Creates missing columns that usually aren't included as they weren't
### originally a part of the match template that volunteers use.
if(!("xG" %in% colnames(df))) (df$xG <- NA)
if(!("poss.number" %in% colnames(df))) (df$poss.number <- NA)
if(!("def.number" %in% colnames(df))) (df$def.number <- NA)

##5. FILL IN MISSING TIME DATA---------
## Fills in missing time data. This assumes that, if there are blanks, the first row where 
## a minute appears is the first event for that minute.
kickoff.row <- grep("kickoff", df[,"poss.action"])
#### in case there's more than one "kickoff" (incorrectly) logged, set kickoff.row as the first kickoff
if(length(kickoff.row) > 1) (kickoff.row <- kickoff.row[1])
rownum <- kickoff.row
rm(kickoff.row)
#### Runs a while loop that checks if a given row has a missing time value
#### ands adds the appropriate value
while (rownum <= nrow(df)) {
  #checks if time column is blank or is a "-"
  if (df[rownum,"time"] == "-" | is.na(df[rownum,"time"])) {
    #if time column is blank or a "-", set it as whatever the time is in the above row
    df[rownum,"time"] <- df[rownum-1, "time"]
  }
  rownum <- rownum + 1
}
rm(rownum)

##6. RECALCULATE VALUES IN "EVENT" COLUMN---------
### Runs a while loop that looks for "-"'s and blank values in "event" column
### and assigns them as NA values
rownum <- 1
while (rownum <= nrow(df)) {
  if (df[rownum,"event"] == "-" | is.na(df[rownum,"event"]) | df[rownum,"event"] == " ") {
    df[rownum,"event"] <- NA
  }
  rownum <- rownum + 1
}
rm(rownum)
### Now, find the number of the row after kickoff
kickoff.row <- grep("kickoff", df[,"poss.action"])
### in case there's more than one "kickoff" (incorrectly) logged, set kickoff.row as the first kickoff
if(length(kickoff.row) > 1) (kickoff.row <- kickoff.row[1])
rownum <- kickoff.row
rm(kickoff.row)
rownum <- rownum + 1
### Checks if "poss.player" is NA, "-", or " " and sets appropriate event value
### The logic here is that if the "poss.player" column is blank, then whatever else
### is in that row is part of the same event as the row above it (assuming it's all
### been logged correctly).
while (rownum <= nrow(df)) {
  if(df[rownum,"poss.player"] == "-" | 
     is.na(df[rownum,"poss.player"]) | 
     df[rownum,"poss.player"] == " ") {
    #sets event value as previous row's event value
    df[rownum,"event"] <- df[rownum-1,"event"]
  } else {
    #sets event value as 1 plus previous row's event value
    df[rownum,"event"] <- df[rownum-1,"event"] + 1
  }
  rownum <- rownum + 1
}
rm(rownum)

##7. CLEAN UP PLAYER NUMBERS AND NAMES
### Gets rid of player numbers and leading/trailing whitespace 
### in "poss.player" and "def.player" values
### NOTE: THIS WILL LIKELY NEED TO BE CHANGED (OR GOTTEN RID OF)
### WHEN IT COMES TO ADDRESSING THE ISSUE OF HOW TO ACCOUNT FOR MATCHES
### WITH PLAYERS THAT SHARE LAST NAMES
rownum <- 1
while (rownum <= nrow(df)) {
  poss.string <- df[rownum,"poss.player"]
  def.string <- df[rownum,"def.player"]
  df[rownum,"poss.player"] <- trimws(strsplit(as.character(poss.string)," \\(")[[1]][1])
  df[rownum,"def.player"] <- trimws(strsplit(as.character(def.string)," \\(")[[1]][1])
  rownum <- rownum + 1
}
rm(rownum)

##8. CREATE METADATA OBJECTS----------
### Creates a meta data frame of all columns from row 1 to row before kickoff
ref <- df[1:(grep("kickoff", df[,"poss.action"])[1]-1),]
### Creates a vector for the "home" team and the "away" team, excluding possible NA values
teams <- as.character(unique(ref$poss.team))
teams <- teams[!is.na(teams) & !(teams=="-") & !(teams==" ") & !(teams=="")]
hometeam <- teams[1]
awayteam <- teams[2]
### home team should always be listed first
homedata <- ref[ref[,"poss.team"]==hometeam,c("poss.position","poss.team","poss.number", "poss.player")]
awaydata <- ref[ref[,"poss.team"]==awayteam,c("poss.position","poss.team","poss.number" ,"poss.player")]
## Create data frame with opposites of each location
posslocations <- c("A6", "A18", "A3L", "A3C", "A3R", "AM3L", "AM3C", 
                   "AM3R", "DM3L", "DM3C", "DM3R", "D3L", "D3C", "D3R", 
                   "D18", "D6", "AL", "AC", "AR", "AML", "AMC", 
                   "AMR", "DML", "DMC", "DMR", "DL", "DC", "DR")
deflocations <- c("D6", "D18", "D3R", "D3C", "D3L", "DM3R", "DM3C",
                  "DM3L", "AM3R", "AM3C", "AM3L", "A3R", "A3C", "A3L", 
                  "A18", "A6", "DR", "DC", "DL", "DMR", "DMC",
                  "DML", "AMR", "AMC", "AML", "AR", "AC", "AL")
opposites <- data.frame(posslocations, deflocations)

##9. CLEANS UP UPPERCASE ERRORS IN PLAYER NAMES-------
### Checks if a player's name has certain letters in upper case 
### which messes with how creating-stats.R reads the final csv file
kickoff.row <- grep("kickoff", df[,"poss.action"])
### in case there's more than one "kickoff" (incorrectly) logged, set kickoff.row as the first kickoff
if(length(kickoff.row) > 1) (kickoff.row <- kickoff.row[1])
rownum <- kickoff.row
rm(kickoff.row)
rownum <- rownum + 1
####creates vector of players, excluding blanks
players <- as.character(unique(ref$poss.player))
players <- players[!is.na(players) & !(players=="-") & !(players==" ") & !(players=="")]
while (rownum <= nrow(df)) {
  #checks if poss.player has a value in the column
  if(!is.na(df[rownum,"poss.player"])){
    y <- 1
    while (y <= length(players)) {
      if (((tolower(df[rownum,"poss.player"])==tolower(players[y]))) & 
          (df[rownum,"poss.player"] != players[y])) {
        df[rownum,"poss.player"] <- players[y]
      }
      y <- y + 1
    }
  }
  #checks if def.player has a value in the column
  if(!is.na(df[rownum,"def.player"])){
    z <- 1
    while (z <= length(players)) {
      if (((tolower(df[rownum,"def.player"])==tolower(players[z]))) & 
          (df[rownum,"def.player"] != players[z])) {
        df[rownum,"def.player"] <- players[z]
      }
      z <- z + 1
    }
  }
  rownum <- rownum + 1
}
rm(x,y,z,rownum)

##10. CALCULATE MISSING TEAM & POSITION DATA FOR EACH PLAYER---------
### Deletes metadata from df & converts "-", " ", and blank values to NAs
df <- df[grep("kickoff", df[,"poss.action"])[1]:nrow(df),]
df[(df) == "-"] <- NA
df[(df) == " "] <- NA
df[(df) == ""] <- NA
###Goes down df and pairs each number-name combination with the appropriate team value
x <- 1
while (x <= nrow(df)) {
  poss.string <- paste(unlist(df[x,c("poss.number","poss.player")],recursive=TRUE), sep="", collapse=" ")
  def.string <- paste(unlist(df[x,c("def.number","def.player")],recursive=TRUE), sep="", collapse=" ")
  y <- 1
  while (y <= nrow(ref)) {
    if(poss.string == paste(unlist(ref[y,c("poss.number","poss.player")],recursive=TRUE), sep="", collapse=" ")) {
      df[x,c("poss.team")] <- ref[y,"poss.team"]
      df[x,c("poss.position")] <- ref[y,"poss.position"]
    }
    if(def.string == paste(unlist(ref[y,c("poss.number","poss.player")],recursive=TRUE), sep="", collapse=" ")) {
      df[x,c("def.team")] <- ref[y,"poss.team"]
      df[x,c("def.position")] <- ref[y,"poss.position"]
    }
    y <- y + 1
  }
  x <- x + 1
}
rm(x,y,poss.string,def.string,ref)

##11. CREATES THE INVERTIBLE FUNCTION----------
##Function to determine if an action's location is invertible based on the
##location of certain opposing players' action
actionIsInvertible <- function(action, col) {
  grepl("pressure|challenge|aerial|tackle|dispossess|dribble|pass|move|take|shots",df[action, col])
}

##12. EXPANDS SHORTCUT VALUES FOR MATCH ACTIONS----------
x <- 1
while (x <= nrow(df)) {
  ##Convert "poss.action" shortcuts
  if (grepl("^sgk", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "shots.stopped.by.gk"
  }
  if (grepl("^sdef", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "shots.stopped.by.def"
  }
  if (grepl("^sb", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "shots.blocked"
  }
  if (grepl("^sc", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "shots.scored"
  }
  if (grepl("^sm", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "shots.missed"
  }
  if (grepl("^pf", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "passes.f"
  }
  if (grepl("^ps", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "passes.s"
  }
  if (grepl("^pb", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "passes.b"
  }
  if (grepl("^m", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "movement"
  }
  if (grepl("^tkw", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "take.on.won"
  }
  if (grepl("^tkl", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "take.on.lost"
  }
  if (grepl("^d", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "dispossessed"
  }
  if (grepl("^lt", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "lost.touch"
  }
  if (grepl("^aw", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "aerial.won"
  }
  if (grepl("^al", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "aerial.lost"
  }
  if (grepl("^r", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "recoveries"
  }
  if (grepl("^bs", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "ball.shield"
  }
  if (grepl("^cl", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "clearances"
  }
  if (grepl("^playcutoff", df[x,"poss.action"])) {
    df[x,"poss.action"] <- "playcutoffbybroadcast"
  }
  ##Convert "play.type" shortcuts
  if (grepl("^th ", df[x,"play.type"])) {
    df[x,"play.type"] <- "through"
  }
  if (grepl("^lay", df[x,"play.type"])) {
    df[x,"play.type"] <- "lay.off"
  }
  if (grepl("^cc", df[x,"play.type"])) {
    df[x,"play.type"] <- "corner.crosses"
  }
  if (grepl("^dc", df[x,"play.type"])) {
    df[x,"play.type"] <- "deep.crosses"
  }
  if (grepl("^s", df[x,"play.type"])) {
    df[x,"play.type"] <- "switch"
  }
  if (grepl("^lay", df[x,"play.type"])) {
    df[x,"play.type"] <- "lay.off"
  }
  if (grepl("^flick", df[x,"play.type"])) {
    df[x,"play.type"] <- "flick.on"
  }
  if (grepl("^ti", df[x,"play.type"])) {
    df[x,"play.type"] <- "throw.in"
  }
  if (grepl("^fk", df[x,"play.type"])) {
    df[x,"play.type"] <- "free.kick"
  }
  if (grepl("^h", df[x,"play.type"])) {
    df[x,"play.type"] <- "headed"
  }
  if (grepl("^ck", df[x,"play.type"])) {
    df[x,"play.type"] <- "corner.kick"
  }
  if (grepl("^gk$|^gk ", df[x,"play.type"])) {
    df[x,"play.type"] <- "goal.kick"
  }
  if (grepl("^gkt", df[x,"play.type"])) {
    df[x,"play.type"] <- "gk.throws"
  }
  if (grepl("^gkdk", df[x,"play.type"])) {
    df[x,"play.type"] <- "gk.drop.kick"
  }
  if (grepl("^pk", df[x,"play.type"])) {
    df[x,"play.type"] <- "penalty.kick"
  }
  ##Convert "def.action" shortcuts
  if (grepl("^dbs", df[x,"def.action"])) {
    df[x,"def.action"] <- "ball.shield"
  }
  if (grepl("^bs", df[x,"def.action"])) {
    df[x,"def.action"] <- "ball.shield"
  }
  if (grepl("^dis", df[x,"def.action"])) {
    df[x,"def.action"] <- "dispossessed"
  }
  if (grepl("^ds", df[x,"def.action"])) {
    df[x,"def.action"] <- "dispossessed"
  }
  if (grepl("^dlt", df[x,"def.action"])) {
    df[x,"def.action"] <- "dispossessed"
  }
  if (grepl("^tb", df[x,"def.action"])) {
    df[x,"def.action"] <- "tackles.ball"
  }
  if (grepl("^tba", df[x,"def.action"])) {
    df[x,"def.action"] <- "tackles.ball.away"
  }
  if (grepl("^tbw", df[x,"def.action"])) {
    df[x,"def.action"] <- "tackles.ball.won"
  }
  if (grepl("^dtm", df[x,"def.action"])) {
    df[x,"def.action"] <- "dribbled.tackles.missed"
  }
  if (grepl("^dor", df[x,"def.action"])) {
    df[x,"def.action"] <- "dribbled.out.run"
  }
  if (grepl("^dt", df[x,"def.action"])) {
    df[x,"def.action"] <- "dribbled.turned"
  }
  if (grepl("^p", df[x,"def.action"])) {
    df[x,"def.action"] <- "pressured"
  }
  if (grepl("^ch", df[x,"def.action"])) {
    df[x,"def.action"] <- "challenged"
  }
  if (grepl("^bl", df[x,"def.action"])) {
    df[x,"def.action"] <- "blocks"
  }
  if (grepl("^int", df[x,"def.action"])) {
    df[x,"def.action"] <- "interceptions"
  }
  if (grepl("^bd", df[x,"def.action"])) {
    df[x,"def.action"] <- "ball.shield"
  }
  if (grepl("^cl", df[x,"def.action"])) {
    df[x,"def.action"] <- "clearances"
  }
  if (grepl("^aw", df[x,"def.action"])) {
    df[x,"def.action"] <- "aerial.won"
  }
  if (grepl("^al", df[x,"def.action"])) {
    df[x,"def.action"] <- "aerial.lost"
  }
  ##Convert "poss.player.disciplinary" shortcuts
  if (grepl("^fw", df[x,"poss.player.disciplinary"])) {
    df[x,"poss.player.disciplinary"] <- "fouls.won"
  }
  if (grepl("^fc", df[x,"poss.player.disciplinary"])) {
    df[x,"poss.player.disciplinary"] <- "fouls.conceded"
  }
  ##Convert "poss.notes" shortcuts
  if (grepl("^keep.poss|^kept.poss", df[x,"poss.notes"])) {
    df[x,"poss.notes"] <- "out.of.bounds.keep.poss"
  }
  if (grepl("^lost.poss|^lose", df[x,"poss.notes"])) {
    df[x,"poss.notes"] <- "out.of.bounds.lost.poss"
  }
  ##Convert "def.player.disciplinary" shortcuts
  if (grepl("^fw", df[x,"def.player.disciplinary"])) {
    df[x,"def.player.disciplinary"] <- "fouls.won"
  }
  if (grepl("^fc", df[x,"def.player.disciplinary"])) {
    df[x,"def.player.disciplinary"] <- "fouls.conceded"
  }
  x <- x + 1
}
rm(x)

##13. FILLS IN BLANK DEF.LOCATION CELLS----------
## Goes down the entire data.frame, row by row, and fills in blank "def.location" cells
cantDetermine <- c()
x <- 1
while (x <= nrow(df)) {
  ## checks if "def.location" is NA for actions that can have their location determined
  ## based on the inverse of certain actions from opposing players
  if (is.na(df[x,"def.location"])) {
    col <- "def.action"
    if (actionIsInvertible(x, col)) {
      ## Check if "poss.location is filled in for event
      ev <- df[x,"event"]
      possloc <- df[df[,"event"]==ev,"poss.location"][1]
      if(!is.na(possloc)) {
        # assign the opposite of poss.loc "def.location"
        df[x,"def.location"] <- as.character(opposites[as.character(opposites[,"posslocations"]) == as.character(possloc),"deflocations"])
      }
      ## if "poss.location" is an NA, we can't determine the blank "def.location" value
      else if (is.na(df[x, "poss.location"])) {
        paste(x, "has an NA poss.location value")
      }
    } 
    ## checks if "def.location" is blank for interceptions, which can have its location
    ## determined based on location of next action, which is by definition by the intercepting
    ## player at the location of the interception
    else if (grepl("interceptions", df[x,"def.action"])) {
      # find location of next poss.player
      e <- df[x,"event"][1]
      ne <- e + 1
      location <- df[df[,"event"] == df[ne,"event"],"poss.location"][1]
      # assign it as the "def.location"
      df[x,"def.location"] <- location
    }
    ## Otherwise, NA values "def.location" can't be determined
    else {
      if(!is.na(df[x,"def.action"])){
        cantDetermine <- c(cantDetermine, df[x,"event"])
      }
    }
  }
  x <- x + 1
}
rm(x, e, ev, ne, possloc,col,location)
print("The following events have blank def.location")
cantDetermine
rm(cantDetermine)

##14. FILLS IN BLANK POSS.LOCATION CELLS & DETERMINE COMPLETED PASSES----------
e <- 1
while (e <= max(df$event, na.rm = TRUE)) {
  # get row for "poss.action" for "event"
  row <- grep(e,df[,"event"])[1]
  # get event value and row for "poss.action" for next event
  nextevent <- e + 1
  nextrow <- grep(nextevent,df[,"event"])[1]
  # checks these conditions which must be fulfilled for the pass attempt to be a completed pass
  if(
    # checks if the event is a pass attempt
    grepl("pass", df[df[,"event"] == e,"poss.action"][1]) &&
    
    # checks if the "poss.play.destination" value is blank and needs to be filled
    #don't remember why I put this in and don't think it's necessary
    #is.na(df[row,"poss.play.destination"]) &&
    
    # checks if the next event isn't a stop in play or break in broadcast
    # these instances should have the "poss.play.destination" value filled in anyways
    !grepl("playcutoffbybroadcast|offside|stoppage|
           substitution|halftime|fulltime|end.of", df[nextrow,"poss.action"]) &&
    
    # checks if next event isn't a lost aerial duel
    !grepl("aerial.lost", df[nextrow, "poss.action"]) &&
    
    # checks if next event, which shouldn't be a lost aerial duel, has the same team as the possessing team
    df[row,"poss.team"] == df[nextrow,"poss.team"] &&
    
    # if the above conditions are satisfied, check "def.action" to make sure it does not
    # include defensive actions that would still indicate an unsuccessful pass attempt
    !grepl("interceptions|blocks|clearances|shield|high.balls.won|smothers.won|loose.balls.won", df[df[,"event"] == e,"def.action"])
    )
    # if the previous test is passed, then it's a completed pass! Now, to determine the destination of the pass
    {
    # use location from the next event as
    # the poss.play.destination value
    df[row,"poss.play.destination"] <- df[nextrow, "poss.location"]
    
    # one last thing, add a ".c" to the end of the "poss.action" value to signify that it's a completed pass
    string <- df[row,"poss.action"]
    df[row,"poss.action"] <- paste0(string, ".c")
    
    # move on to the next event
    e <- e + 1
  }
    # if the previous test is not passed, then the event is not a completed pass
    # move on to the next event
  else {
    e <- e + 1
  }
}
rm(e, nextevent, nextrow, row, string)

##15. [THIS CODE NOT IN NOT IN USE] FILLS IN BLANK POSS.PLAY.DESTINATION CELLS--------
#For when defensive action can be used to determine "poss.play.destination"
#df$poss.play.destination <- as.character(df$poss.action)
#e <- 1
#while (e <= length(unique(df$event))){
#  #check if is a nonblank poss action of a certain type with blank poss play dest. value
#  if (!is.na(df[df[,"event"]==e,"poss.action"][1]) & is.na(df[df[,"event"]==e,"poss.play.destination"][1])){
#    #check if any def actions are of a certain type
#    if(grepl("interception|blocks|clearances|ball.shield",
#             paste(unlist(strsplit(df[df[,"event"] == e,"def,action"], ","),
#                          recursive=TRUE), sep="", collapse=" "))) {
#      #if ball shield present, set this as the destination
#    }
#  }
#}

rm(opposites, deflocations, awayteam, hometeam, posslocations, homedata, 
   awaydata, teams, players, rosters, actionIsInvertible, match)
