package com.stash.nativedemo;

import android.content.pm.ActivityInfo;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.switchmaterial.SwitchMaterial;

import com.stash.popup.StashPayCard;

/**
 * Sample activity demonstrating StashPayCard SDK integration.
 * Features separate sections for Checkout and Modal with their own advanced options.
 */
public class MainActivity extends AppCompatActivity {
    private static final String TAG = "StashNativeDemo";
    
    private static final String DEFAULT_URL = "https://htmlpreview.github.io/?https://raw.githubusercontent.com/stashgg/stash-unity/refs/heads/main/.github/Stash.Popup.Test/index.html";
    
    private EditText checkoutUrlInput;
    private EditText modalUrlInput;
    private TextView statusText;
    
    // Advanced options toggles
    private TextView advancedCheckoutToggle;
    private TextView advancedModalToggle;
    private LinearLayout advancedCheckoutContainer;
    private LinearLayout advancedModalContainer;
    private boolean isCheckoutAdvancedExpanded = false;
    private boolean isModalAdvancedExpanded = false;
    
    // Modal config values (read from sliders when opening modal)
    private SwitchMaterial modalShowDragBarSwitch;
    private SwitchMaterial modalAllowDismissSwitch;
    private SeekBar modalPhonePortraitWidthSlider;
    private SeekBar modalPhonePortraitHeightSlider;
    private SeekBar modalPhoneLandscapeWidthSlider;
    private SeekBar modalPhoneLandscapeHeightSlider;
    private SeekBar modalTabletPortraitWidthSlider;
    private SeekBar modalTabletPortraitHeightSlider;
    private SeekBar modalTabletLandscapeWidthSlider;
    private SeekBar modalTabletLandscapeHeightSlider;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        // Initialize StashPayCard
        StashPayCard stashPayCard = StashPayCard.getInstance();
        stashPayCard.setActivity(this);
        
        // URL inputs
        checkoutUrlInput = findViewById(R.id.checkoutUrlInput);
        modalUrlInput = findViewById(R.id.modalUrlInput);
        checkoutUrlInput.setText(DEFAULT_URL);
        modalUrlInput.setText(DEFAULT_URL);
        
        statusText = findViewById(R.id.statusText);
        
        // Buttons
        Button openCheckoutButton = findViewById(R.id.openCheckoutButton);
        Button openModalButton = findViewById(R.id.openModalButton);
        
        // Advanced options containers
        advancedCheckoutToggle = findViewById(R.id.advancedCheckoutToggle);
        advancedModalToggle = findViewById(R.id.advancedModalToggle);
        advancedCheckoutContainer = findViewById(R.id.advancedCheckoutContainer);
        advancedModalContainer = findViewById(R.id.advancedModalContainer);
        
        // Checkout advanced options toggles
        advancedCheckoutToggle.setOnClickListener(v -> {
            isCheckoutAdvancedExpanded = !isCheckoutAdvancedExpanded;
            updateAdvancedVisibility();
        });
        
        advancedModalToggle.setOnClickListener(v -> {
            isModalAdvancedExpanded = !isModalAdvancedExpanded;
            updateAdvancedVisibility();
        });
        
        // ==================== CHECKOUT ADVANCED OPTIONS ====================
        
        SwitchMaterial webViewModeSwitch = findViewById(R.id.webViewModeSwitch);
        SwitchMaterial landscapeLockSwitch = findViewById(R.id.landscapeLockSwitch);
        
        webViewModeSwitch.setOnCheckedChangeListener((buttonView, isChecked) -> {
            stashPayCard.setForceWebBasedCheckout(isChecked);
            statusText.setText("Mode: " + (isChecked ? "Web View (Chrome)" : "Card UI"));
        });
        
        landscapeLockSwitch.setOnCheckedChangeListener((buttonView, isChecked) -> {
            if (isChecked) {
                setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
                statusText.setText("Locked to Landscape");
            } else {
                setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
                statusText.setText("Orientation Unlocked");
            }
        });
        
        // Phone card height slider
        TextView phoneCardHeightLabel = findViewById(R.id.phoneCardHeightLabel);
        SeekBar phoneCardHeightSlider = findViewById(R.id.phoneCardHeightSlider);
        phoneCardHeightSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                phoneCardHeightLabel.setText(String.format("Height: %d%%", progress + 10));
                stashPayCard.setCardHeightRatioPortrait((progress + 10) / 100f);
            }
        });
        
        // Checkout tablet portrait sliders
        TextView checkoutTabletPortraitWidthLabel = findViewById(R.id.checkoutTabletPortraitWidthLabel);
        SeekBar checkoutTabletPortraitWidthSlider = findViewById(R.id.checkoutTabletPortraitWidthSlider);
        checkoutTabletPortraitWidthSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                checkoutTabletPortraitWidthLabel.setText(String.format("Width: %d%%", progress + 10));
                stashPayCard.setTabletWidthRatioPortrait((progress + 10) / 100f);
            }
        });
        
        TextView checkoutTabletPortraitHeightLabel = findViewById(R.id.checkoutTabletPortraitHeightLabel);
        SeekBar checkoutTabletPortraitHeightSlider = findViewById(R.id.checkoutTabletPortraitHeightSlider);
        checkoutTabletPortraitHeightSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                checkoutTabletPortraitHeightLabel.setText(String.format("Height: %d%%", progress + 10));
                stashPayCard.setTabletHeightRatioPortrait((progress + 10) / 100f);
            }
        });
        
        // Checkout tablet landscape sliders
        TextView checkoutTabletLandscapeWidthLabel = findViewById(R.id.checkoutTabletLandscapeWidthLabel);
        SeekBar checkoutTabletLandscapeWidthSlider = findViewById(R.id.checkoutTabletLandscapeWidthSlider);
        checkoutTabletLandscapeWidthSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                checkoutTabletLandscapeWidthLabel.setText(String.format("Width: %d%%", progress + 10));
                stashPayCard.setTabletWidthRatioLandscape((progress + 10) / 100f);
            }
        });
        
        TextView checkoutTabletLandscapeHeightLabel = findViewById(R.id.checkoutTabletLandscapeHeightLabel);
        SeekBar checkoutTabletLandscapeHeightSlider = findViewById(R.id.checkoutTabletLandscapeHeightSlider);
        checkoutTabletLandscapeHeightSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                checkoutTabletLandscapeHeightLabel.setText(String.format("Height: %d%%", progress + 10));
                stashPayCard.setTabletHeightRatioLandscape((progress + 10) / 100f);
            }
        });
        
        // Apply initial checkout sizing
        stashPayCard.setCardHeightRatioPortrait((phoneCardHeightSlider.getProgress() + 10) / 100f);
        stashPayCard.setTabletWidthRatioPortrait((checkoutTabletPortraitWidthSlider.getProgress() + 10) / 100f);
        stashPayCard.setTabletHeightRatioPortrait((checkoutTabletPortraitHeightSlider.getProgress() + 10) / 100f);
        stashPayCard.setTabletWidthRatioLandscape((checkoutTabletLandscapeWidthSlider.getProgress() + 10) / 100f);
        stashPayCard.setTabletHeightRatioLandscape((checkoutTabletLandscapeHeightSlider.getProgress() + 10) / 100f);
        
        // ==================== MODAL ADVANCED OPTIONS ====================
        
        modalShowDragBarSwitch = findViewById(R.id.modalShowDragBarSwitch);
        modalAllowDismissSwitch = findViewById(R.id.modalAllowDismissSwitch);
        
        // Modal phone portrait sliders
        TextView modalPhonePortraitWidthLabel = findViewById(R.id.modalPhonePortraitWidthLabel);
        modalPhonePortraitWidthSlider = findViewById(R.id.modalPhonePortraitWidthSlider);
        modalPhonePortraitWidthSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                modalPhonePortraitWidthLabel.setText(String.format("Width: %d%%", progress + 10));
            }
        });
        
        TextView modalPhonePortraitHeightLabel = findViewById(R.id.modalPhonePortraitHeightLabel);
        modalPhonePortraitHeightSlider = findViewById(R.id.modalPhonePortraitHeightSlider);
        modalPhonePortraitHeightSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                modalPhonePortraitHeightLabel.setText(String.format("Height: %d%%", progress + 10));
            }
        });
        
        // Modal phone landscape sliders
        TextView modalPhoneLandscapeWidthLabel = findViewById(R.id.modalPhoneLandscapeWidthLabel);
        modalPhoneLandscapeWidthSlider = findViewById(R.id.modalPhoneLandscapeWidthSlider);
        modalPhoneLandscapeWidthSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                modalPhoneLandscapeWidthLabel.setText(String.format("Width: %d%%", progress + 10));
            }
        });
        
        TextView modalPhoneLandscapeHeightLabel = findViewById(R.id.modalPhoneLandscapeHeightLabel);
        modalPhoneLandscapeHeightSlider = findViewById(R.id.modalPhoneLandscapeHeightSlider);
        modalPhoneLandscapeHeightSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                modalPhoneLandscapeHeightLabel.setText(String.format("Height: %d%%", progress + 10));
            }
        });
        
        // Modal tablet portrait sliders
        TextView modalTabletPortraitWidthLabel = findViewById(R.id.modalTabletPortraitWidthLabel);
        modalTabletPortraitWidthSlider = findViewById(R.id.modalTabletPortraitWidthSlider);
        modalTabletPortraitWidthSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                modalTabletPortraitWidthLabel.setText(String.format("Width: %d%%", progress + 10));
            }
        });
        
        TextView modalTabletPortraitHeightLabel = findViewById(R.id.modalTabletPortraitHeightLabel);
        modalTabletPortraitHeightSlider = findViewById(R.id.modalTabletPortraitHeightSlider);
        modalTabletPortraitHeightSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                modalTabletPortraitHeightLabel.setText(String.format("Height: %d%%", progress + 10));
            }
        });
        
        // Modal tablet landscape sliders
        TextView modalTabletLandscapeWidthLabel = findViewById(R.id.modalTabletLandscapeWidthLabel);
        modalTabletLandscapeWidthSlider = findViewById(R.id.modalTabletLandscapeWidthSlider);
        modalTabletLandscapeWidthSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                modalTabletLandscapeWidthLabel.setText(String.format("Width: %d%%", progress + 10));
            }
        });
        
        TextView modalTabletLandscapeHeightLabel = findViewById(R.id.modalTabletLandscapeHeightLabel);
        modalTabletLandscapeHeightSlider = findViewById(R.id.modalTabletLandscapeHeightSlider);
        modalTabletLandscapeHeightSlider.setOnSeekBarChangeListener(new SimpleSeekBarListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                modalTabletLandscapeHeightLabel.setText(String.format("Height: %d%%", progress + 10));
            }
        });
        
        // ==================== EVENT LISTENER ====================
        
        stashPayCard.setListener(new StashPayCard.StashPayListener() {
            @Override
            public void onPaymentSuccess() {
                Log.i(TAG, "Payment successful");
                runOnUiThread(() -> {
                    statusText.setText("Payment Success");
                    Toast.makeText(MainActivity.this, "Payment successful", Toast.LENGTH_SHORT).show();
                });
            }
            
            @Override
            public void onPaymentFailure() {
                Log.i(TAG, "Payment failed");
                runOnUiThread(() -> {
                    statusText.setText("Payment Failed");
                    Toast.makeText(MainActivity.this, "Payment failed", Toast.LENGTH_SHORT).show();
                });
            }
            
            @Override
            public void onDialogDismissed() {
                Log.i(TAG, "Dialog dismissed");
                runOnUiThread(() -> statusText.setText("Dialog dismissed"));
            }
            
            @Override
            public void onOptInResponse(String optinType) {
                Log.i(TAG, "Opt-in response: " + optinType);
                runOnUiThread(() -> statusText.setText("Opt-in: " + optinType));
            }
            
            @Override
            public void onPageLoaded(long loadTimeMs) {
                Log.i(TAG, "Page loaded in " + loadTimeMs + "ms");
            }
        });
        
        // ==================== BUTTON HANDLERS ====================
        
        openCheckoutButton.setOnClickListener(v -> {
            String url = checkoutUrlInput.getText().toString().trim();
            if (!url.isEmpty()) {
                statusText.setText("Opening checkout...");
                stashPayCard.openCheckout(url);
            } else {
                Toast.makeText(this, "Please enter a checkout URL", Toast.LENGTH_SHORT).show();
            }
        });
        
        openModalButton.setOnClickListener(v -> {
            String url = modalUrlInput.getText().toString().trim();
            if (!url.isEmpty()) {
                statusText.setText("Opening modal...");
                StashPayCard.ModalConfig config = buildModalConfig();
                stashPayCard.openModal(url, config);
            } else {
                Toast.makeText(this, "Please enter a modal URL", Toast.LENGTH_SHORT).show();
            }
        });
    }
    
    private StashPayCard.ModalConfig buildModalConfig() {
        StashPayCard.ModalConfig config = new StashPayCard.ModalConfig();
        config.showDragBar = modalShowDragBarSwitch.isChecked();
        config.allowDismiss = modalAllowDismissSwitch.isChecked();
        config.phoneWidthRatioPortrait = (modalPhonePortraitWidthSlider.getProgress() + 10) / 100f;
        config.phoneHeightRatioPortrait = (modalPhonePortraitHeightSlider.getProgress() + 10) / 100f;
        config.phoneWidthRatioLandscape = (modalPhoneLandscapeWidthSlider.getProgress() + 10) / 100f;
        config.phoneHeightRatioLandscape = (modalPhoneLandscapeHeightSlider.getProgress() + 10) / 100f;
        config.tabletWidthRatioPortrait = (modalTabletPortraitWidthSlider.getProgress() + 10) / 100f;
        config.tabletHeightRatioPortrait = (modalTabletPortraitHeightSlider.getProgress() + 10) / 100f;
        config.tabletWidthRatioLandscape = (modalTabletLandscapeWidthSlider.getProgress() + 10) / 100f;
        config.tabletHeightRatioLandscape = (modalTabletLandscapeHeightSlider.getProgress() + 10) / 100f;
        return config;
    }
    
    @Override
    protected void onResume() {
        super.onResume();
        StashPayCard.getInstance().setActivity(this);
    }
    
    private void updateAdvancedVisibility() {
        advancedCheckoutContainer.setVisibility(isCheckoutAdvancedExpanded ? View.VISIBLE : View.GONE);
        advancedCheckoutToggle.setText(isCheckoutAdvancedExpanded ? "▼ Advanced Options - Checkout" : "▶ Advanced Options - Checkout");
        
        advancedModalContainer.setVisibility(isModalAdvancedExpanded ? View.VISIBLE : View.GONE);
        advancedModalToggle.setText(isModalAdvancedExpanded ? "▼ Advanced Options - Modal" : "▶ Advanced Options - Modal");
    }
    
    /** Simple SeekBar listener with empty start/stop methods */
    private abstract static class SimpleSeekBarListener implements SeekBar.OnSeekBarChangeListener {
        @Override public void onStartTrackingTouch(SeekBar seekBar) {}
        @Override public void onStopTrackingTouch(SeekBar seekBar) {}
    }
}
