package com.stash.nativedemo;

import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.lifecycle.ViewModelProvider;
import androidx.recyclerview.widget.LinearLayoutManager;

import com.stash.popup.StashPayCard;

import com.stash.nativedemo.databinding.ActivityMainBinding;

/**
 * Sample activity demonstrating StashPayCard SDK integration.
 * Follows Google Android best practices: ViewBinding, ViewModel, RecyclerView list (Settings pattern).
 */
public class MainActivity extends AppCompatActivity {

    private static final String TAG = "StashNativeDemo";

    private ActivityMainBinding binding;
    private MainViewModel viewModel;
    private SettingsAdapter adapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        viewModel = new ViewModelProvider(this).get(MainViewModel.class);
        adapter = new SettingsAdapter(viewModel, new SettingsAdapter.Callbacks() {
            @Override
            public void onOpenCheckout() {
                openCheckout();
            }

            @Override
            public void onOpenModal() {
                openModal();
            }

        });

        binding.recyclerView.setLayoutManager(new LinearLayoutManager(this));
        binding.recyclerView.setAdapter(adapter);

        viewModel.getItems().observe(this, items -> {
            if (items != null) {
                adapter.submitList(items);
                syncViewModelToStashPayCard();
            }
        });

        StashPayCard stashPayCard = StashPayCard.getInstance();
        stashPayCard.setActivity(this);
        stashPayCard.setListener(new StashPayCard.StashPayListener() {
            @Override
            public void onPaymentSuccess() {
                Log.i(TAG, "Payment successful");
                runOnUiThread(() -> {
                    viewModel.setStatus("Payment Success");
                    Toast.makeText(MainActivity.this, "Payment successful", Toast.LENGTH_SHORT).show();
                });
            }

            @Override
            public void onPaymentFailure() {
                Log.i(TAG, "Payment failed");
                runOnUiThread(() -> {
                    viewModel.setStatus("Payment Failed");
                    Toast.makeText(MainActivity.this, "Payment failed", Toast.LENGTH_SHORT).show();
                });
            }

            @Override
            public void onDialogDismissed() {
                Log.i(TAG, "Dialog dismissed");
                runOnUiThread(() -> viewModel.setStatus("Dialog dismissed"));
            }

            @Override
            public void onOptInResponse(String optinType) {
                Log.i(TAG, "Opt-in response: " + optinType);
                runOnUiThread(() -> viewModel.setStatus("Opt-in: " + optinType));
            }

            @Override
            public void onPageLoaded(long loadTimeMs) {
                Log.i(TAG, "Page loaded in " + loadTimeMs + "ms");
            }

            @Override
            public void onNetworkError() {
                Log.e(TAG, "Network error");
                runOnUiThread(() -> {
                    viewModel.setStatus("Network Error");
                    Toast.makeText(MainActivity.this, "Network error - could not load page", Toast.LENGTH_SHORT).show();
                });
            }
        });

        viewModel.refreshList();
    }

    private void syncViewModelToStashPayCard() {
        StashPayCard card = StashPayCard.getInstance();
        card.setForceWebBasedCheckout(viewModel.isWebViewMode());
        card.setForcePortraitOnCheckout(viewModel.isForcePortraitOnCheckout());
        card.setCardHeightRatioPortrait((viewModel.getPhoneCardHeight() + 10) / 100f);
        card.setCardWidthRatioLandscape((viewModel.getCheckoutPhoneLandscapeW() + 10) / 100f);
        card.setCardHeightRatioLandscape((viewModel.getCheckoutPhoneLandscapeH() + 10) / 100f);
        card.setTabletWidthRatioPortrait((viewModel.getCheckoutTabletPortraitW() + 10) / 100f);
        card.setTabletHeightRatioPortrait((viewModel.getCheckoutTabletPortraitH() + 10) / 100f);
        card.setTabletWidthRatioLandscape((viewModel.getCheckoutTabletLandscapeW() + 10) / 100f);
        card.setTabletHeightRatioLandscape((viewModel.getCheckoutTabletLandscapeH() + 10) / 100f);
    }

    private void openCheckout() {
        String url = viewModel.getCheckoutUrl();
        if (url == null || url.trim().isEmpty()) {
            Toast.makeText(this, R.string.error_checkout_url, Toast.LENGTH_SHORT).show();
            return;
        }
        viewModel.setStatus("Opening checkout...");
        syncViewModelToStashPayCard();
        StashPayCard.getInstance().openCheckout(url.trim());
    }

    private void openModal() {
        String url = viewModel.getModalUrl();
        if (url == null || url.trim().isEmpty()) {
            Toast.makeText(this, R.string.error_modal_url, Toast.LENGTH_SHORT).show();
            return;
        }
        viewModel.setStatus("Opening modal...");
        StashPayCard.ModalConfig config = buildModalConfig();
        StashPayCard.getInstance().openModal(url.trim(), config);
    }

    private StashPayCard.ModalConfig buildModalConfig() {
        StashPayCard.ModalConfig config = new StashPayCard.ModalConfig();
        config.showDragBar = viewModel.isModalShowDragBar();
        config.allowDismiss = viewModel.isModalAllowDismiss();
        config.phoneWidthRatioPortrait = (viewModel.getModalPhonePortraitW() + 10) / 100f;
        config.phoneHeightRatioPortrait = (viewModel.getModalPhonePortraitH() + 10) / 100f;
        config.phoneWidthRatioLandscape = (viewModel.getModalPhoneLandscapeW() + 10) / 100f;
        config.phoneHeightRatioLandscape = (viewModel.getModalPhoneLandscapeH() + 10) / 100f;
        config.tabletWidthRatioPortrait = (viewModel.getModalTabletPortraitW() + 10) / 100f;
        config.tabletHeightRatioPortrait = (viewModel.getModalTabletPortraitH() + 10) / 100f;
        config.tabletWidthRatioLandscape = (viewModel.getModalTabletLandscapeW() + 10) / 100f;
        config.tabletHeightRatioLandscape = (viewModel.getModalTabletLandscapeH() + 10) / 100f;
        return config;
    }

    @Override
    protected void onResume() {
        super.onResume();
        StashPayCard.getInstance().setActivity(this);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        binding = null;
    }
}
