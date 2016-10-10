
## Load necessary packages

library(R.utils)
library(quanteda)
library(doParallel)
library(pander)
library(Cairo)
library(data.table)
library(stringi)
library(dplyr)
# library(caret)


## Download necessary files

if(!file.exists("dirty")){
    dirtyUrl <- "https://raw.githubusercontent.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/master/en"
    download.file(dirtyUrl, destfile="dirty", mode="wb")
    rm(dirtyUrl)
}

if(!file.exists("Coursera-SwiftKey.zip")){
    dataUrl <- "https://d396qusza40orc.cloudfront.net/dsscapstone/dataset/Coursera-SwiftKey.zip"
    download.file(dataUrl, destfile="Coursera-SwiftKey.zip", mode="wb")
    rm(dataUrl)
}

if(!file.exists("./final")){
    unzip("Coursera-SwiftKey.zip", exdir=".")
}


## Use Parallel Cores to Process

parallelizeTask <- function(task, ...) {
    # Calculate the number of cores
    ncores <- detectCores() - 1
    # Initiate cluster
    cl <- makeCluster(ncores)
    registerDoParallel(cl)
    # print("Starting task")
    r <- task(...)
    # print("Task complete")
    stopCluster(cl)
    r
}


## Initial Data Cleaning and Exploration

#### Create a function that processes each file

initialClean <- function(path){
    
    ## import file
    con <- file(path, open="rb")
    doc <- readLines(con, encoding="UTF-8", skipNul=TRUE)
    close(con)
    
    ## remove control and unicode characters
    doc <- iconv(doc, "latin1", "ASCII", sub="")
    doc <- gsub(pattern="[[:cntrl:]]", replacement="", x=doc)
    
    ## replace websites
    doc <- gsub(pattern="[[:alnum:]]+://([[:alnum:]]\\.)?(.+)\\.([[:alnum:]]+)/?([[:alnum:]]*[[:punct:]]*)*", replacement="website", x=doc)
    ## replace emails
    doc <- gsub(pattern="[[:alnum:]]+[_|\\.]*[[:alnum:]]*@[[:alnum:]]+(_|-|\\.)*[[:alnum:]]*\\.[[:alnum:]]+", replacement="email", x=doc)
    ## replace hashtags
    doc <- gsub(pattern="#[[:alpha:]]+(_*[[:alnum:]]*)*", replacement="hashtag", x=doc)
    ## replace twitter handles
    doc <- gsub(pattern=" @[[:alnum:]]+_*[[:alnum:]]*", replacement="twitterhandle", x=doc)
    ## remove remaining words joined by @ symbols
    doc <- gsub(pattern="[[:alnum:]]+(_|-|\\.)*[[:alnum:]]*@[[:alnum:]]+", replacement="", x=doc)
    ## replace hyphens and slashes with spaces
    doc <- gsub(pattern="[-|/|\\]", replacement=" ", x=doc)
    
    ## save out new copy of the file
    saveAs <- gsub(pattern=".*/", replacement="", x=blogsPath)
    saveAs <- gsub(pattern="(\\.)[[:alnum:]]*$", replacement="", saveAs)
    saveAs <- paste("./en_US_corpus/", saveAs, "Clean.txt", sep="")
    suppressWarnings(if(!file.exists("./en_US_corpus/")){dir.create("./en_US_corpus")})
    write(doc, saveAs)
    
    ## return cleaned file
    return(doc)
}

#### Load the paths

blogsPath <- "./final/en_US/en_US.blogs.txt"
newsPath <- "./final/en_US/en_US.news.txt"
twitterPath <- "./final/en_US/en_US.twitter.txt"

#### Process files with multiple cores

blogsClean <- parallelizeTask(initialClean, blogsPath)
newsClean <- parallelizeTask(initialClean, newsPath)
twitterClean <- parallelizeTask(initialClean, twitterPath)
rm(blogsPath, newsPath, twitterPath)


## Create a Corpus of Training Data

#### Split each dataset into training sets (totaling 65%) and a testing set (35%)

set.seed(12345)

blogs_splitIndex01 <- sample(length(blogsClean), length(blogsClean)*0.8)
blogs_temp <- blogsClean[blogs_splitIndex01]
blogs_test <- blogsClean[-blogs_splitIndex01]
rm(blogsClean, blogs_splitIndex01)
blogs_splitIndex02 <- sample(length(blogs_temp), length(blogs_temp)*0.5)
blogs_train01 <- blogs_temp[blogs_splitIndex02]
blogs_train02 <- blogs_temp[-blogs_splitIndex02]
rm(blogs_temp, blogs_splitIndex02)

news_splitIndex01 <- sample(length(newsClean), length(newsClean)*0.8)
news_temp <- newsClean[news_splitIndex01]
news_test <- newsClean[-news_splitIndex01]
rm(newsClean, news_splitIndex01)
news_splitIndex02 <- sample(length(news_temp), length(news_temp)*0.5)
news_train01 <- news_temp[news_splitIndex02]
news_train02 <- news_temp[-news_splitIndex02]
rm(news_temp, news_splitIndex02)

twitter_splitIndex01 <- sample(length(twitterClean), length(twitterClean)*0.8)
twitter_temp <- twitterClean[twitter_splitIndex01]
twitter_test <- twitterClean[-twitter_splitIndex01]
rm(twitterClean, twitter_splitIndex01)
twitter_splitIndex02 <- sample(length(twitter_temp), length(twitter_temp)*0.5)
twitter_train01 <- twitter_temp[twitter_splitIndex02]
twitter_train02 <- twitter_temp[-twitter_splitIndex02]
rm(twitter_temp, twitter_splitIndex02)

train01 <- c(blogs_train01, news_train01, twitter_train01)
rm(blogs_train01, news_train01, twitter_train01)
train02 <- c(blogs_train02, news_train02, twitter_train02)
rm(blogs_train02, news_train02, twitter_train02)
test <- c(blogs_test, news_test, twitter_test)
rm(blogs_test, news_test, twitter_test)
gc()

if(!file.exists("./train_test_sets")){
    dir.create("./train_test_sets")
}

saveRDS(train01, "./train_test_sets/train01.rds")
saveRDS(train02, "./train_test_sets/train02.rds")
saveRDS(test, "./train_test_sets/test.rds")


## Create processing functions

#### Load vector of profanity to be removed

dirty <- read.csv("dirty", header=FALSE, stringsAsFactors=FALSE)
dirty <- dirty$V1
dirty <- dirty[1:376]

#### Subfunction that trims out all ngrams with a frequency of 1, then finds 
#### ngrams where there are 20 or more of the same prefix with high frequencies 
#### and then removes all ngrams with that prefix that have a frequency of 2

trimNgrams <- function(ngramTable){
    
    ngramTable <- subset(ngramTable, freq>1)
    prefix_highFreq_table <- table(ngramTable$prefix)
    prefix_highFreq_table <- prefix_highFreq_table[prefix_highFreq_table>30]
    prefix_highFreq <- names(prefix_highFreq_table)
    ngramTable <- ngramTable[!(ngramTable$prefix %in% prefix_highFreq & ngramTable$freq==2), ]
    
}

#### Function that takes processed data and outputs a data.table of ngram frequencies

makeNgramTable <- function(data, ngramLevel){
    
    corpus <- corpus(data)
    corpusTokenized <- tokenize(corpus, what="sentence", simplify=TRUE)
    rm(corpus)
    dfm <- dfm(corpusTokenized, ngrams=ngramLevel, toLower=TRUE, removeNumbers = TRUE, 
               removePunct = TRUE, removeSeparators = TRUE, concatenator=" ",
               ignoredFeatures=dirty, stem=FALSE)
    rm(corpusTokenized)
    freq <- colSums(dfm)
    rm(dfm)
    ngram <- names(freq)
    words <- stri_count_boundaries(ngram[1])
    regex <- paste(rep("([[:alpha:]]+)", times=words-1), collapse=" ")
    prefix <- stri_extract_first(ngram, regex=regex)
    pred <- stri_extract_last_words(ngram)
    ngramTable <- data.table(prefix, pred, freq)
    setkey(ngramTable, prefix, pred)
    ngramTable <- ngramTable[!is.na(prefix)]
    ngramTable <- ngramTable[, list(freq=sum(freq)), by=list(prefix, pred)]
    ngramTable <- trimNgrams(ngramTable)
    return(ngramTable)
    
}

#### Function that takes processed data and outputs a data.table of ngram
#### frequencies, modified specifically for unigrams

makeUnigramTable <- function(data, ngramLevel){
    
    corpus <- corpus(data)
    corpusTokenized <- tokenize(corpus, what="sentence", simplify=TRUE)
    rm(corpus)
    dfm <- dfm(corpusTokenized, ngrams=ngramLevel, toLower=TRUE, removeNumbers = TRUE, 
               removePunct = TRUE, removeSeparators = TRUE, concatenator=" ",
               ignoredFeatures=dirty, stem=FALSE)
    rm(corpusTokenized)
    freq <- colSums(dfm)
    rm(dfm)
    pred <- names(freq)
    ngramTable <- data.table(pred, freq)
    setkey(ngramTable, pred)
    ngramTable <- ngramTable[!is.na(pred)]
    ngramTable <- ngramTable[, list(freq=sum(freq)), by=list(pred)]
    ngramTable <- subset(ngramTable, freq>1)
    return(ngramTable)
    
}

#### Function that processes and combines the ngram training sets

ngramTraining <- function(file01, file02, ngramLevel){
    
    ngram_train01 <- makeNgramTable(file01, ngramLevel)
    ngram_train02 <- makeNgramTable(file02, ngramLevel)
    
    ngram_train <- merge(ngram_train01, ngram_train02, all=TRUE)
    rm(ngram_train01, ngram_train02)
    ngram_train[is.na(ngram_train)] <- 0
    ngram_train <- mutate(ngram_train, freq=freq.x+freq.y)
    ngram_train <- subset(ngram_train, select=c(prefix, pred, freq))
    ngram_train <- ngram_train[, list(freq=sum(freq)), by=list(prefix, pred)]
    
    setorder(ngram_train, -freq)
    setkey(ngram_train, prefix)
    
}

#### Function that processes and combines the unigram training sets

unigramTraining <- function(file01, file02, ngramLevel){
    unigram_train01 <- makeUnigramTable(file01, ngramLevel)
    unigram_train02 <- makeUnigramTable(file02, ngramLevel)
    
    unigram_train <- merge(unigram_train01, unigram_train02, all=TRUE)
    rm(unigram_train01, unigram_train02)
    unigram_train[is.na(unigram_train)] <- 0
    unigram_train <- mutate(unigram_train, freq=freq.x+freq.y)
    unigram_train <- subset(unigram_train, select=c(pred, freq))
    unigram_train <- unigram_train[, list(freq=sum(freq)), by=list(pred)]
    
    setorder(unigram_train, -freq)
    
}

#### Function that processes the testing set

ngramTesting <- function(file01, ngramLevel){
    ngram_test <- makeNgramTable(file01, ngramLevel)
    setorder(ngram_test, -freq)
    setkey(ngram_test, prefix)
}


## Create ngram tables and indexes, and write these out to files

#### make dir for files
if(!file.exists("./database")){
    dir.create("./database")
}


#### make quadgrams
gc()
quadgram_train <- parallelizeTask(ngramTraining, train01, train02, 4)
quadgram_train_size <- object.size(quadgram_train)
saveRDS(quadgram_train, "./database/quadgram_train.rds")
rm(quadgram_train)

#### make trigrams

gc()
trigram_train <- parallelizeTask(ngramTraining, train01, train02, 3)
trigram_train_size <- object.size(trigram_train)
saveRDS(trigram_train, "./database/trigram_train.rds")
rm(trigram_train)

#### make bigrams
gc()
bigram_train <- parallelizeTask(ngramTraining, train01, train02, 2)
bigram_train_size <- object.size(bigram_train)
saveRDS(bigram_train, "./database/bigram_train.rds")
rm(bigram_train)

#### make unigrams
gc()
unigram_train <- parallelizeTask(unigramTraining, train01, train02, 1)
unigram_train_size <- object.size(unigram_train)
saveRDS(unigram_train, "./database/unigram_train.rds")
rm(unigram_train)

### make quadgram test file
gc()
quadgram_test <- parallelizeTask(ngramTesting, test, 4)
quadgram_test_size <- object.size(quadgram_test)
quadgram_test_size
saveRDS(quadgram_test, "./database/quadgram_test.rds")
rm(quadgram_test)

#### clean up workspace
rm(train01, train02, test, dirty)
gc()


## Look at object sizes

ngramTable_sizes <- data.frame(unigram_train = as.numeric(unigram_train_size), 
                               bigram_train = as.numeric(bigram_train_size), 
                               trigram_train = as.numeric(trigram_train_size), 
                               quadgram_train = as.numeric(quadgram_train_size),
                               total_training = as.numeric(unigram_train_size 
                                                           + bigram_train_size
                                                           + trigram_train_size 
                                                           + quadgram_train_size), 
                               quadgram_test = as.numeric(quadgram_test_size))
sizes_mb <- paste(round(ngramTable_sizes[1,]/2^20, digits=2), rep("MB"))
ngramTable_sizes <- rbind(ngramTable_sizes, sizes_mb)
rm(sizes_mb)
ngramTable_sizes


## Read in data
unigram_train <- readRDS("./database/unigram_train.rds")
bigram_train <- readRDS("./database/bigram_train.rds")
trigram_train <- readRDS("./database/trigram_train.rds")
quadgram_train <- readRDS("./database/quadgram_train.rds")


## Prediction Algorithm

#### Function to clean input string

cleanString <- function(string){
    
    ## remove control characters, emojis, etc
    string <- iconv(string, "latin1", "ASCII", sub="")
    string <- gsub(pattern="[[:cntrl:]]", replacement="", x=string)
    ## replace websites
    string <- gsub(pattern="[[:alnum:]]+://([[:alnum:]]\\.)?(.+)\\.([[:alnum:]]+)/?([[:alnum:]]*[[:punct:]]*)*", replacement="website", x=string)
    ## replace emails
    string <- gsub(pattern="[[:alnum:]]+[_|\\.]*[[:alnum:]]*@[[:alnum:]]+(_|-|\\.)*[[:alnum:]]*\\.[[:alnum:]]+", replacement="email", x=string)
    ## replace hashtags
    string <- gsub(pattern="#[[:alpha:]]+(_*[[:alnum:]]*)*", replacement="hashtag", x=string)
    ## replace twitter handles
    string <- gsub(pattern=" @[[:alnum:]]+_*[[:alnum:]]*", replacement="twitterhandle", x=string)
    ## remove remaining words joined by @ symbols
    string <- gsub(pattern="[[:alnum:]]+(_|-|\\.)*[[:alnum:]]*@[[:alnum:]]+", replacement="", x=string)
    ## replace hyphens and slashes with spaces
    string <- gsub(pattern="[-|/|\\]", replacement=" ", x=string)
    ## remove remaining punctuation
    string <- gsub(pattern="[[:punct:]]", replacement="", x=string)
    ## remove numbers (and anything before them? though this might screw up ngrams, since they've just had numbers removed)
    string <- gsub(pattern="[[:digit:]]", replacement="", x=string)
    ## strip extra whitespace in string
    #### stringi function?
    string <- gsub(pattern="\\s+", replacement=" ", x=string) 
    ## remove extra space around string
    string <- gsub(pattern="^\\s|\\s$", replacement="", x=string)
    ## make strings lowercase
    string <- tolower(string)
    ## trim to 3 or less last words (also space around string)
    num <- stri_count_boundaries(string)
    if(num>3){
        string <- stri_extract_last(string, regex="[[:alpha:]]+ [[:alpha:]]+ [[:alpha:]]+$")
        return(string)
    } else {
        return(string)
    }
    
}

#### Function to automate prediction algorithm

predictWord <- function(string, numberPred){
    
    ## detect number of remaining words in string
    num <- stri_count_boundaries(string)
    
    ## subset predictions, based on number of words in string
    if (num==3) {
        
        quadgram_pred <- quadgram_train[.(string)]
        quadgram_num <- sum(quadgram_pred$freq)
        quadgram_pred$prob <- quadgram_pred$freq/quadgram_num
        quadgram_pred <- quadgram_pred[, .(pred, prob)]
        setkey(quadgram_pred, pred)
        string_minus_one <- stri_extract_last(string, regex="[[:alpha:]]+ [[:alpha:]]+$")
        trigram_pred <- trigram_train[.(string_minus_one)]
        trigram_num <- sum(trigram_pred$freq)
        trigram_pred$prob <- (trigram_pred$freq/trigram_num) * 0.4
        trigram_pred <- trigram_pred[, .(pred, prob)]
        setkey(trigram_pred, pred)
        predictions <- merge(quadgram_pred, trigram_pred, all=TRUE)
        predictions <- predictions[!is.na(predictions$pred)]
        predictions[is.na(predictions)] <- 0
        predictions <- mutate(predictions, prob = prob.x + prob.y)
        predictions <- predictions[, .(pred, prob)]
        setkey(predictions, pred)
        string_minus_two <- stri_extract_last(string, regex="[[:alpha:]]+$")
        bigram_pred <- bigram_train[.(string_minus_two)]
        bigram_num <- sum(bigram_pred$freq)
        bigram_pred$prob <- (bigram_pred$freq/bigram_num) * 0.4 * 0.4
        bigram_pred <- bigram_pred[, .(pred, prob)]
        setkey(bigram_pred, pred)
        predictions <- merge(predictions, bigram_pred, all=TRUE)
        predictions <- predictions[!is.na(predictions$pred)]
        predictions[is.na(predictions)] <- 0
        predictions <- mutate(predictions, prob = prob.x + prob.y)
        predictions <- predictions[, .(pred, prob)]
        
        predictions <- predictions[!is.na(pred)]
        predictions <- predictions[, list(prob=sum(prob)), by=list(pred)]
        setkey(predictions, NULL)
        
        if (dim(predictions)[1]>=numberPred) {
            
            setorder(predictions, -prob)
            predictions <- predictions[1:numberPred, ]
            
        } else {
            
            unigram_pred <- unigram_train[1:numberPred, ]
            unigram_num <- sum(unigram_train$freq)
            unigram_pred$prob <- (unigram_pred$freq/unigram_num) * 0.4 * 0.4 * 0.4
            predictions <- rbind(predictions, unigram_pred[, .(pred, prob)])
            predictions <- predictions[, list(prob=sum(prob)), by=list(pred)]
            setorder(predictions, -prob)
            predictions <- predictions[1:numberPred, ]
            
        }
        
    } else if (num==2) {
        
        trigram_pred <- trigram_train[.(string)]
        trigram_num <- sum(trigram_pred$freq)
        trigram_pred$prob <- trigram_pred$freq/trigram_num
        trigram_pred <- trigram_pred[, .(pred, prob)]
        setkey(trigram_pred, pred)
        string_minus_one <- stri_extract_last(string, regex="[[:alpha:]]+$")
        bigram_pred <- bigram_train[.(string_minus_one)]
        bigram_num <- sum(bigram_pred$freq)
        bigram_pred$prob <- (bigram_pred$freq/bigram_num) * 0.4
        bigram_pred <- bigram_pred[, .(pred, prob)]
        setkey(bigram_pred, pred)
        predictions <- merge(trigram_pred, bigram_pred, all=TRUE)
        predictions <- predictions[!is.na(predictions$pred)]
        predictions[is.na(predictions)] <- 0
        predictions <- mutate(predictions, prob = prob.x + prob.y)
        predictions <- predictions[, .(pred, prob)]
        
        predictions <- predictions[!is.na(pred)]
        predictions <- predictions[, list(prob=sum(prob)), by=list(pred)]
        setkey(predictions, NULL)
        
        if (dim(predictions)[1]>=numberPred) {
            
            setorder(predictions, -prob)
            predictions <- predictions[1:numberPred, ]
            
        } else {
            
            unigram_pred <- unigram_train[1:numberPred, ]
            unigram_num <- sum(unigram_train$freq)
            unigram_pred$prob <- (unigram_pred$freq/unigram_num) * 0.4 * 0.4
            predictions <- rbind(predictions, unigram_pred[, .(pred, prob)])
            predictions <- predictions[, list(prob=sum(prob)), by=list(pred)]
            setorder(predictions, -prob)
            predictions <- predictions[1:numberPred, ]
            
        }
        
    } else if (num==1) {
        
        bigram_pred <- bigram_train[.(string)]
        bigram_num <- sum(bigram_pred$freq)
        bigram_pred$prob <- bigram_pred$freq/bigram_num
        predictions <- bigram_pred[, .(pred, prob)]
        predictions <- predictions[!is.na(pred)]
        predictions <- predictions[, list(prob=sum(prob)), by=list(pred)]
        setkey(predictions, NULL)
        
        if (dim(predictions)[1]>=numberPred) {
            
            setorder(predictions, -prob)
            predictions <- predictions[1:numberPred, ]
            
        } else {
            
            unigram_pred <- unigram_train[1:numberPred, ]
            unigram_num <- sum(unigram_train$freq)
            unigram_pred$prob <- (unigram_pred$freq/unigram_num) * 0.4
            predictions <- rbind(predictions, unigram_pred[, .(pred, prob)])
            predictions <- predictions[, list(prob=sum(prob)), by=list(pred)]
            setorder(predictions, -prob)
            predictions <- predictions[1:numberPred, ]
            
        }
        
    } else {
        
        predictions <- unigram_train[1:numberPred, ]
        num <- sum(predictions$freq)
        predictions$prob <- (predictions$freq/num)
        predictions <- predictions[, .(pred, prob)]
        setorder(predictions, -prob)
        
    }
    
    ## return specified number of predictions, sorted by probability
    return(predictions)
    
}

#### Function to combine cleaning and prediction

cleanAndPredict <- function(string, numberPred){
    string <- cleanString(string)
    predictWord(string, numberPred)
}

#### Time Prediction

testString <- "Well hey! Monkey see, monkey "
system.time(timePred <- cleanAndPredict(testString, 5))


## Out-of-Sample accuracy test

#### Read in quadgram_test data

quadgram_test <- readRDS("./database/quadgram_test.rds")
quadgram_test <- subset(quadgram_test, select=c(prefix, pred))

#### Create subfunction for detecting whether or not the true prediction is in a 
#### list of predicted values

truePredictions <- function(string, pred, numberPred){
    
    string_pred <- predictWord(string, numberPred)
    value <- pred %in% string_pred$pred
    value
    
}

#### Create function to apply truePredictions() to a n-gram table

predictionAccuracy <- function(ngramTable, numberPred) {
    
    length <- dim(ngramTable)[1]
    strings <- ngramTable$prefix
    preds <- ngramTable$pred
    ngramTable_truePred <- mapply(function(x,y) truePredictions(x, y, numberPred), strings, preds)
    accuracy <- sum(ngramTable_truePred)/length
    accuracy
    
}

#### Determine accuracy of predictions on the 'quadgram_test' data set

set.seed(54321)
quadgram_test_subset_rows <- sample(nrow(quadgram_test), 100000)
quadgram_test_subset <- quadgram_test[quadgram_test_subset_rows]

gc()
accuracy_first5pred <- predictionAccuracy(quadgram_test_subset, 5)
accuracy_first5pred
# [1] 0.63804
accuracy_first25pred <- predictionAccuracy(quadgram_test_subset, 25)
accuracy_first25pred
# [1] 0.83764






## Possible things to improve:

#### replace websites and etc with a string
#### improve unigram assignment by attempting to identify part of speech?
#### table of unigram predictions based on part of speech, if detectable? (ing, ed, es, etc)
