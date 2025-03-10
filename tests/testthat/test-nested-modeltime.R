

# MODELTIME NESTED (ITERATIVE) FORECASTING -----

# Requires the modeltime_nested branch until merge
# remotes::install_github("business-science/modeltime@modeltime_nested")


library(testthat)
library(tidymodels)
library(modeltime)
library(tidyverse)
library(timetk)


# DATA PREP FUNCTIONS ----

data_prep_tbl <- walmart_sales_weekly %>%
    select(id, Date, Weekly_Sales) %>%
    set_names(c("id", "date", "value"))

tib_1 <- data_prep_tbl %>%
    filter(id %in% c("1_1", "1_3"))

tib_2 <- data_prep_tbl %>%
    filter(id %in% c("1_8")) %>%
    slice_tail( n= 10)

data_start_tbl <- bind_rows(tib_1, tib_2)



# NESTED DATA ----

nested_data_tbl <- data_start_tbl %>%

    extend_timeseries(
        .id_var        = id,
        .date_var      = date,
        .length_future = 52
    ) %>%

    # >> Can add xregs in here <<

    nest_timeseries(
        .id_var        = id,
        .length_future = 52,
        .length_actual = 52*2
    ) %>%

    split_nested_timeseries(
        .length_test = 52
    )


# MODELING ----

# * XGBoost ----

rec_xgb <- recipe(value ~ ., extract_nested_train_split(nested_data_tbl)) %>%
    step_timeseries_signature(date) %>%
    step_rm(date) %>%
    step_zv(all_predictors()) %>%
    step_dummy(all_nominal_predictors(), one_hot = TRUE)

wflw_xgb <- workflow() %>%
    add_model(boost_tree("regression") %>% set_engine("xgboost")) %>%
    add_recipe(rec_xgb)

# * Bad Model ----
#   - Xgboost can't handle dates

recipe_bad <- recipe(value ~ ., extract_nested_train_split(nested_data_tbl))

wflw_bad <- workflow() %>%
    add_model(boost_tree()) %>%
    add_recipe(recipe_bad)

# * Prophet ----
# rec_prophet <- recipe(value ~ date, extract_nested_train_split(nested_data_tbl))
#
# wflw_prophet <- workflow() %>%
#     add_model(
#         prophet_reg("regression", seasonality_yearly = TRUE) %>%
#             set_engine("prophet")
#     ) %>%
#     add_recipe(rec_prophet)


# NESTED WORKFLOW ----

# * Test 1: Good + Bad Model ----

testthat::test_that("modeltime_nested_fit: Good + Bad Model", {

    # ** Fit ----
    expect_warning({
        nested_modeltime_tbl <- nested_data_tbl %>%
            modeltime_nested_fit(
                wflw_xgb,
                wflw_bad,
                # wflw_prophet,

                control = control_nested_fit(verbose = TRUE)
            )
    })


    attrib <- attributes(nested_modeltime_tbl)

    expect_equal(attrib$fit_column, ".splits")
    expect_equal(attrib$id, "id")

    acc_tbl <- nested_modeltime_tbl %>% extract_nested_test_accuracy()

    expect_equal(nrow(acc_tbl), 6)
    expect_equal(ncol(acc_tbl), 10)

    err_tbl <- nested_modeltime_tbl %>% extract_nested_error_report()

    expect_equal(nrow(err_tbl), 4)

    fcast_tbl <- nested_modeltime_tbl %>%
        extract_nested_test_forecast()

    # fcast_tbl %>% group_by(id) %>% plot_modeltime_forecast()

    expect_equal(nrow(fcast_tbl), 312)
    expect_equal(ncol(fcast_tbl), 8)

    fcast_tbl <- nested_modeltime_tbl %>%
        extract_nested_test_forecast(.include_actual = F)

    expect_equal(nrow(fcast_tbl), 104)
    expect_equal(ncol(fcast_tbl), 8)

    fcast_tbl <- nested_modeltime_tbl %>%
        extract_nested_test_forecast(.include_actual = F, .id_subset = "1_1")

    expect_equal(nrow(fcast_tbl), 52)
    expect_equal(ncol(fcast_tbl), 8)

    # ** Select Best ----

    expect_warning(
        best_nested_modeltime_tbl <- nested_modeltime_tbl %>%
            modeltime_nested_select_best(metric = "rsq", minimize = FALSE)
    )


    best_model_report <- best_nested_modeltime_tbl %>%
        extract_nested_best_model_report()

    expect_equal(nrow(best_model_report), 3)
    expect_equal(ncol(best_model_report), 10)

    fcast_tbl <- best_nested_modeltime_tbl %>%
        extract_nested_test_forecast()

    # fcast_tbl %>% group_by(id) %>% plot_modeltime_forecast()

    expect_equal(nrow(fcast_tbl), 313)
    expect_equal(ncol(fcast_tbl), 8)

    # ** Refit ----

    expect_warning({
        nested_modeltime_refit_tbl <- best_nested_modeltime_tbl %>%
            modeltime_nested_refit(
                control = control_nested_refit(verbose = TRUE)
            )
    })

    nested_modeltime_refit_tbl %>% extract_nested_error_report()

    fcast_tbl <- nested_modeltime_refit_tbl %>%
        extract_nested_future_forecast()

    expect_equal(nrow(fcast_tbl), 312)
    expect_equal(ncol(fcast_tbl), 8)

    # fcast_tbl %>% group_by(id) %>% plot_modeltime_forecast()


})


# * Test 2: Bad Model ----
testthat::test_that("modeltime_nested_fit: Bad Model Only", {

    # ** Fit ----
    expect_warning({
        nested_modeltime_tbl <- nested_data_tbl %>%
            modeltime_nested_fit(
                # wflw_xgb,
                wflw_bad,

                control = control_nested_fit(verbose = TRUE)
            )
    })


    attrib <- attributes(nested_modeltime_tbl)

    expect_equal(attrib$fit_column, ".splits")
    expect_equal(attrib$id, "id")

    acc_tbl <- nested_modeltime_tbl %>% extract_nested_test_accuracy()

    expect_equal(nrow(acc_tbl), 3)
    expect_equal(ncol(acc_tbl), 3)

    err_tbl <- nested_modeltime_tbl %>% extract_nested_error_report()

    expect_equal(nrow(err_tbl), 3)
    expect_equal(ncol(err_tbl), 4)

    fcast_tbl <- nested_modeltime_tbl %>%
        extract_nested_test_forecast()

    # fcast_tbl %>% group_by(id) %>% plot_modeltime_forecast()

    expect_equal(nrow(fcast_tbl), 0)
    expect_equal(ncol(fcast_tbl), 0)

    fcast_tbl <- nested_modeltime_tbl %>%
        extract_nested_test_forecast(.include_actual = F)

    expect_equal(nrow(fcast_tbl), 0)
    expect_equal(ncol(fcast_tbl), 0)

    fcast_tbl <- nested_modeltime_tbl %>%
        extract_nested_test_forecast(.include_actual = F, .id_subset = "1_1")

    expect_equal(nrow(fcast_tbl), 0)
    expect_equal(ncol(fcast_tbl), 0)

    # ** Select Best ----

    expect_error({
        nested_modeltime_tbl %>%
            modeltime_nested_select_best(metric = "rsq", minimize = FALSE)
    })


    # ** Refit ----

    expect_warning({
        nested_modeltime_refit_tbl <- nested_modeltime_tbl %>%
            modeltime_nested_refit(
                control = control_nested_refit(verbose = TRUE)
            )
    })

    nested_modeltime_refit_tbl %>% extract_nested_error_report()

    fcast_tbl <- nested_modeltime_refit_tbl %>%
        extract_nested_future_forecast(.include_actual = F)

    expect_equal(nrow(fcast_tbl), 0)
    expect_equal(ncol(fcast_tbl), 0)

    # fcast_tbl %>%
    #     group_by(id) %>%
    #     plot_modeltime_forecast()


})





