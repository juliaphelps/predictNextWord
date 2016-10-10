# Description of Prediction Algorithm





The *Predict Next Word* app is designed to predict a possible next word in a 
sentence or phrase based upon the previous words. It allows the user to type in 
a string of any length, which is then cleaned and shortened to the last three 
words in the string. This cleaned string is then used to predict the next word, 
utilizing a set of predefined ngram tables and their corresponding frequencies. 
Over a sample of 100,000 strings, the algorithm has an out-of-sample accuracy of 
~63.8% within the top five predictions, and an out-of-sample accuracy of ~83.8% 
within the top 25 predictions.

This application is designed to satisfy the requirements of the *Data Science 
Specialization Capstone Project*, offered by John Hopkins University through 
[Coursera.org](http://www.coursera.org).

_____

### About the Data

Data used in this assignment was provided by [SwiftKey](https://swiftkey.com/en), 
in conjunction with [Coursera.org](http://www.coursera.org), and is used with 
permission. The raw data is sampled from a corpora called 
[HC Corpora](http://www.corpora.heliohost.org/), which is gathered by a web 
crawler from publicly available sources. The dataset provided by Coursera.org is 
comprised of three unstructured English text files:


---------------------------------------------------------
File Name         Lines in File   Description            
----------------- --------------- -----------------------
en_US.blogs.txt   899288          text from blogs        

en_US.news.txt    1010242         text from news feeds   

en_US.twitter.txt 2360148         text from twitter feeds
---------------------------------------------------------

For more information about the data, please see the *References* tab.

<br>

### The Process

Due to the very large size of the raw data, it was been pre-processed into 
quadgram, trigram, bigram, and unigram data.tables in a separate process, using 
a random sample of 80% of the total data. The other 20% was reserved as testing 
data, to be used in calculating accuracy. The total process is outlined below:

<br>

#### Cleaning the Data

The initial cleaning function, which was passed over all of the data:

* removed control and Unicode characters, which would otherwise cause the data 
to be read incorrectly
* replaced websites, emails, hashtags, and twitter handles with a relevant tag 
(e.g. hashtags were replaced with the string "hashtag")
* removed additional words joined with '@' symbols (these were often intentional 
misspellings)
* replaced hyphens and colons that conjoined words with a space

Due to its size and the limitations of the author's computer hardware, the data 
was then split evenly into two training sets (representing 80% of the data in 
sum) and a testing set (comprised of the remaining 20% of the data). This made 
it possible to use all of the training data in creating ngram tables, rather 
than only a subset of it. Final training ngram tables were merged after being 
processed.

<br>

#### Processing the Data

The `quanteda` package was chosen to further process, tokenize, and create ngram 
document frequency matrices (DFMs) from the data sets, due in part to its 
performance and ease of use. These DFMs were then summed by term, and sparse 
terms were removed to improve performance of the final prediction algorithm (as 
well as scale them to fit Shiny server limitations) before merging final 
training ngram tables.

In the final ngram tables:

* Additional punctuation, numbers, and excess whitespace were removed.
* Profane words and phrases from the [Shutterstock List of Dirty, Naughty, Obscene, and Otherwise Bad Words](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) 
were removed.
* Remaining words were dropped to lower-case.
* Individual documents were tokenized into sentences, so that ngrams could not 
be created from words in adjacent sentences.
* Document-frequency matrices were created for quadgrams, trigrams, bigrams, and 
unigrams.
* DFMs were summed and split into ngram data.tables with `prefix`, `prediction`, 
and `freq` variables (where applicable).
* Sparse terms within ngram data.tables were removed to improve performance.

A subset of the `quadgram_train` ngram data.table:


-----------------------------------------
&nbsp;       prefix         pred   freq  
------------ -------------- ------ ------
**890030**   he was amazing to     2     

**890031**   he was amazing with   2     

**890032**   he was among   the    24    

**890033**   he was among   those  5     

**890034**   he was among   a      3     

**890035**   he was among   four   2     
-----------------------------------------

<br>

#### Prediction

When a user inputs a string of any length, it is passed through the 
cleanString() function, which cleans it in the same manner as the original raw 
data was cleaned (e.g. removing punctuation, numbers, etc.) and trims it to the 
last three words, if necessary. This "clean string" is then passed through the 
predictWord() function, which detects the final length of the string (3 or less 
words). 

Based on the length of the clean string, the predictWord() function then 
searches the appropriate highest-order ngram data.table for `prefix` matches. It 
calculates probabilities for these matches, based on the equation:

$$Prob(pred|prefix)=\frac{Count(prefix+pred)}{Count(prefix)}$$

It then moves through the lower-order ngram data.tables (down to bigrams) and 
searches for matches, but discounts these using the Stupid Back-off model, which 
back-off weights each lower-level ngram with a predefined $\alpha$ value. As 
suggested in both **Speech and Language Processing** [1] and **Large Language 
Models in Machine Translation** [2], a value of $\alpha=0.4$ is used in 
predictWord().

So, for instance, if the cleaned string has a word length equal to 3:

$$Quadgram Prob=\frac{Count(prefix+pred)}{Count(prefix)}$$
$$Trigram Prob=\frac{Count(prefix+pred)}{Count(prefix)}*\alpha$$
$$Bigram Prob=\frac{Count(prefix+pred)}{Count(prefix)}*\alpha*\alpha$$

If the number of predictions is less than the specified number (set in this app 
to be 25 predictions), then the unigram table is used to fill the remaining 
observation slots. Again, probability is calculated using Stupid Back-off.

<br>

### Accuracy

A subset of the test data, consisting of 100,000 randomly-sampled observations, 
was used to test the accuracy of the prediction function.  Within the top 5 
probabilities, the out-of-sample accuracy was approximately 63.8%; in the top 25 
probabilities, the out-of-sample accuracy was approximately 83.8%.

*Please Note:  This application was built on data from blog, news, and twitter 
feeds. As is suggested in the paper* ***Speech and Language Processing,*** *the 
app will be most accurate when the input string is of a similar source and/or 
structure. For example, the app's accuracy will likely be very diminished if a 
string of Old English words is inputted [1].*

<br>

### Improvements

The accuracy of the predictive algorithm is by no means terrible, given the vast 
complexity of the English language  - and, in particular, the manner in which it 
is used online. However, it could be improved further with more data and more 
computing power to process it, as well as the ability to store a larger dataset 
in a performance-efficient manner within the Shiny host server (or elsewhere).

<br>

### Citation

[1] Jurafsky, Dan, and James H. Martin. *Speech and Language Processing.* Upper 
Saddle River, NJ: Prentice Hall, Pearson Education International, 2014. Print.

[2] Brants, Thorsten, et al. *Large Language Models in Machine Translation.* 2007.

<br>

### Packages Utilized

* `R.utils`
* `quanteda`
* `doParallel`
* `pander`
* `Cairo`
* `data.table`
* `stringi`
* `dplyr`

<br>

### Computer Specifications

*Please Note:  This analysis was designed on a Windows 8 64-bit computer using R 
v3.3.1 and RStudio Version 0.99.902, with all packages up-to-date. Content may 
differ if you run it in a different environment, including, but not limited to: 
function of regular expressions, performance of `quanteda` and other packages, 
appearance of figures and plots, and formatting results of RMarkdown.*

<br>
