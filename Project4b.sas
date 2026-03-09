data defaulted non_defaulted;
set cleaned;
if default_date ne . then output defaulted;
else output non_defaulted;
run;
proc sql;
create table non_defaulted_filter as/*remove the customers who are part of the defaulted dataset*/
select *
from non_defaulted where customer not in (select customer from defaulted)
order by customer, date
;
quit;
data non_defaulted_select temp1;/*select the last record of the non-defaulted*/
set non_defaulted_filter;
by customer date;
if last.customer and last.date then output non_defaulted_select;
else output temp1;
run;
proc sql;/*find relationship length at customer level*/
create table vars as
select customer, count(distinct(year)) as relationship_length, max(arrears) as arrears_flag
from cleaned
group by 1
;
quit;
proc sql;
create table model_rerun_selection as
select distinct a.*, b.relationship_length, b.arrears_flag
from
(select * from defaulted union
select * from non_defaulted_select) as a left join vars as b
on a.customer=b.customer
order by dflt
;
quit;
proc surveyselect data=defaulted method=srs n=5 out=dflt_validation;
run;
proc surveyselect data=non_defaulted_select method=srs n=5 out=non_dflt_validation;
run;
proc sql;
create table validation as
select * from dflt_validation union
select * from non_dflt_validation
;
quit;
proc sql;
create table model_validation as
select distinct a.*, case when b.customer eq . then 1 else 0 end as validation_sample
from model_rerun_selection as a left join validation as b
on a.customer=b.customer
order by customer
;
quit;
proc genmod data=model_validation descending;
Weight validation_sample;
Model dflt = utilisation ltv borrowing_portfolio_ratio postcode_index arrears_flag relationship_length/ dist=binomial;
Output out=preds(where=(validation_sample=0)) p=pred l=lower u=upper;
Run;
Proc sort data=model_validation;
By dflt;
Run;
Proc Means Data=model_validation;
By dflt;
Vars utilisation ltv borrowing_portfolio_ratio postcode_index arrears_flag relationship_length;
Run;
/*Record the data in the Validation Dataset as everytime surveyselect is run randomly the training and validation dataset will change*/
proc sql;
Title "Customers in validaiton dflt selection";
select distinct customer from dflt_validation;
Title "Customers in validaiton non dflt selection";
select distinct customer from non_dflt_validation;
quit;
proc sql;
Title "Prediction of validation dataset";
select customer, dflt as observed_default_status, pred as pred_value format 8.5
from preds
;
quit;
proc logistic data=preds descending;
model dflt = / nofit;
roc "Genmod model" pred=pred;
run;
/*3. Logistic*/
Data validation_customer;
Input Customer;
Datalines;
/*Dflt*/
3342349
6161840
8697888
12095275
35234232
/*Live*/
4232324
7567563
10870633
11228652
24123211
;
run;
proc sql;
create table logistic as
select *
from model_rerun_selection
where customer not in (select customer from validation_customer)
;
quit;
Proc logistic data=logistic;
Model dflt=utilisation ltv borrowing_portfolio_ratio postcode_index arrears_flag
relationship_length;
Run;
/*4 Proc Genmod Probit*/
proc sql;
create table overall as
select distinct a.*, case when b.customer ne . then 0 else 1 end as validation_sample
from model_rerun_selection as a left join validation_customer as b
on a.customer=b.customer
;
quit;
proc genmod data=overall descending;
Weight validation_sample;
model dflt = utilisation borrowing_portfolio_ratio postcode_index arrears_flag
/ dist=binomial link=probit;
output out=preds(where=(validation_sample=0)) p=pred;
ods output parameterestimates=parms;
run;
proc print data=parms noobs;
format estimate 12.10;
var parameter level: estimate;
run;
Proc logistic data=preds descending;
Model dflt= / nofit;
roc "Genmod model" pred=pred;
Run;
Proc corr data=overall;
Var utilisation ltv borrowing_portfolio_ratio postcode_index arrears_flag relationship_length;
Run;