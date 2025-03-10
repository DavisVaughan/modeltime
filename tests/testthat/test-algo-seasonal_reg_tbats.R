# ---- STANDARD ARIMA ----
context("TEST seasonal_reg() - tbats")


# SETUP ----

# Data
m750 <- m4_monthly %>% filter(id == "M750")

# Split Data 80/20
splits <- initial_time_split(m750, prop = 0.8)

# Model Spec
model_spec <- seasonal_reg() %>%
    set_engine("tbats")

# CHECKS ----
test_that("seasonal_reg: checks", {

    # external regressors message
    expect_error({
        seasonal_reg(seasonal_period_1 = 1) %>%
            set_engine("tbats") %>%
            fit(value ~ date, data = training(splits))
    })

})

# PARSNIP ----

test_that("seasonal_reg - tbats: parsnip", {

    skip_on_cran()

    # SETUP

    # Fit Spec
    model_fit <- model_spec %>%
        fit(log(value) ~ date + wday(date, label = TRUE), data = training(splits))

    # Predictions
    predictions_tbl <- model_fit %>%
        modeltime_calibrate(testing(splits)) %>%
        modeltime_forecast(new_data = testing(splits))

    # TEST

    testthat::expect_s3_class(model_fit$fit, "tbats_fit_impl")

    # $fit

    testthat::expect_s3_class(model_fit$fit$models$model_1, "tbats")

    testthat::expect_s3_class(model_fit$fit$data, "tbl_df")

    testthat::expect_equal(names(model_fit$fit$data)[1], "date")

    testthat::expect_true(is.null(model_fit$fit$extras$xreg_recipe))

    # $fit xgboost

    testthat::expect_identical(model_fit$fit$models$model_2, NULL)

    # $preproc

    testthat::expect_equal(model_fit$preproc$y_var, "value")


    # Structure
    testthat::expect_identical(nrow(testing(splits)), nrow(predictions_tbl))
    testthat::expect_identical(testing(splits)$date, predictions_tbl$.index)

    # Out-of-Sample Accuracy Tests

    resid <- testing(splits)$value - exp(predictions_tbl$.value)

    # - Max Error less than 1500
    testthat::expect_lte(max(abs(resid)), 2500)

    # - MAE less than 700
    testthat::expect_lte(mean(abs(resid)), 700)

})



# ---- WORKFLOWS ----

test_that("seasonal_reg: workflow", {

    skip_on_cran()

    # SETUP

    # Recipe spec
    recipe_spec <- recipe(value ~ date, data = training(splits)) %>%
        step_log(value, skip = FALSE) %>%
        step_date(date, features = "dow")

    # Workflow
    wflw <- workflow() %>%
        add_recipe(recipe_spec) %>%
        add_model(model_spec)

    wflw_fit <- wflw %>%
        fit(training(splits))

    # Forecast
    predictions_tbl <- wflw_fit %>%
        modeltime_calibrate(testing(splits)) %>%
        modeltime_forecast(new_data = testing(splits), actual_data = training(splits)) %>%
        mutate_at(vars(.value), exp)

    # TEST

    testthat::expect_s3_class(wflw_fit$fit$fit$fit, "tbats_fit_impl")

    # Structure

    testthat::expect_s3_class(wflw_fit$fit$fit$fit$data, "tbl_df")

    testthat::expect_equal(names(wflw_fit$fit$fit$fit$data)[1], "date")

    testthat::expect_true(is.null(wflw_fit$fit$fit$fit$extras$xreg_recipe))

    # $fit
    testthat::expect_s3_class(wflw_fit$fit$fit$fit$models$model_1, "tbats")

    # $preproc
    mld <- wflw_fit %>% workflows::extract_mold()
    testthat::expect_equal(names(mld$outcomes), "value")


    full_data <- bind_rows(training(splits), testing(splits))

    # Structure
    testthat::expect_identical(nrow(full_data), nrow(predictions_tbl))
    testthat::expect_identical(full_data$date, predictions_tbl$.index)

    # Out-of-Sample Accuracy Tests
    predictions_tbl <- predictions_tbl %>% filter(.key == "prediction")
    resid <- testing(splits)$value - predictions_tbl$.value

    # - Max Error less than 1500
    testthat::expect_lte(max(abs(resid)), 2500)

    # - MAE less than 700
    testthat::expect_lte(mean(abs(resid)), 700)

})




