package com.stash.nativedemo;

import android.content.pm.ActivityInfo;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.constraintlayout.widget.ConstraintLayout;

import com.google.android.material.switchmaterial.SwitchMaterial;

import com.stash.popup.StashPayCard;

/**
 * Sample activity demonstrating StashPayCard SDK integration.
 * Features a two-mode interface with essential controls always visible
 * and advanced options in a collapsible section.
 */
public class MainActivity extends AppCompatActivity {
    private static final String TAG = "StashNativeDemo";
    
    private static final String DEFAULT_URL = "https://htmlpreview.github.io/?https://raw.githubusercontent.com/stashgg/stash-unity/refs/heads/main/.github/Stash.Popup.Test/index.html";
    
    // State preservation keys
    private static final String KEY_URL = "url";
    private static final String KEY_ADVANCED_EXPANDED = "advanced_expanded";
    private static final String KEY_PHONE_CARD_HEIGHT = "phone_card_height";
    private static final String KEY_TABLET_PORTRAIT_WIDTH = "tablet_portrait_width";
    private static final String KEY_TABLET_PORTRAIT_HEIGHT = "tablet_portrait_height";
    private static final String KEY_TABLET_LANDSCAPE_WIDTH = "tablet_landscape_width";
    private static final String KEY_TABLET_LANDSCAPE_HEIGHT = "tablet_landscape_height";
    
    private EditText urlInput;
    private TextView statusText;
    private TextView advancedOptionsToggle;
    private ConstraintLayout advancedOptionsContainer;
    private boolean isAdvancedExpanded = false;
    
    // Sliders
    private SeekBar phoneCardHeightSlider;
    private SeekBar tabletPortraitWidthSlider;
    private SeekBar tabletPortraitHeightSlider;
    private SeekBar tabletLandscapeWidthSlider;
    private SeekBar tabletLandscapeHeightSlider;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        // Initialize views
        urlInput = findViewById(R.id.urlInput);
        statusText = findViewById(R.id.statusText);
        Button openCheckoutButton = findViewById(R.id.openCheckoutButton);
        SwitchMaterial webViewModeSwitch = findViewById(R.id.webViewModeSwitch);
        advancedOptionsToggle = findViewById(R.id.advancedOptionsToggle);
        advancedOptionsContainer = findViewById(R.id.advancedOptionsContainer);
        
        // Size configuration UI - phone card height and tablet portrait/landscape
        TextView phoneCardHeightLabel = findViewById(R.id.phoneCardHeightLabel);
        phoneCardHeightSlider = findViewById(R.id.phoneCardHeightSlider);
        TextView tabletPortraitWidthLabel = findViewById(R.id.tabletPortraitWidthLabel);
        tabletPortraitWidthSlider = findViewById(R.id.tabletPortraitWidthSlider);
        TextView tabletPortraitHeightLabel = findViewById(R.id.tabletPortraitHeightLabel);
        tabletPortraitHeightSlider = findViewById(R.id.tabletPortraitHeightSlider);
        TextView tabletLandscapeWidthLabel = findViewById(R.id.tabletLandscapeWidthLabel);
        tabletLandscapeWidthSlider = findViewById(R.id.tabletLandscapeWidthSlider);
        TextView tabletLandscapeHeightLabel = findViewById(R.id.tabletLandscapeHeightLabel);
        tabletLandscapeHeightSlider = findViewById(R.id.tabletLandscapeHeightSlider);
        
        // Restore state or set defaults (progress 0-90 maps to 10%-100%: progress 58 = 68%, etc.)
        if (savedInstanceState != null) {
            urlInput.setText(savedInstanceState.getString(KEY_URL, DEFAULT_URL));
            isAdvancedExpanded = savedInstanceState.getBoolean(KEY_ADVANCED_EXPANDED, false);
            int phoneH = savedInstanceState.getInt(KEY_PHONE_CARD_HEIGHT, 58);
            int pw = savedInstanceState.getInt(KEY_TABLET_PORTRAIT_WIDTH, 30);
            int ph = savedInstanceState.getInt(KEY_TABLET_PORTRAIT_HEIGHT, 40);
            int lw = savedInstanceState.getInt(KEY_TABLET_LANDSCAPE_WIDTH, 20);
            int lh = savedInstanceState.getInt(KEY_TABLET_LANDSCAPE_HEIGHT, 50);
            phoneCardHeightSlider.setProgress(phoneH);
            phoneCardHeightLabel.setText(String.format("Height: %d%%", phoneH + 10));
            tabletPortraitWidthSlider.setProgress(pw);
            tabletPortraitWidthLabel.setText(String.format("Width: %d%%", pw + 10));
            tabletPortraitHeightSlider.setProgress(ph);
            tabletPortraitHeightLabel.setText(String.format("Height: %d%%", ph + 10));
            tabletLandscapeWidthSlider.setProgress(lw);
            tabletLandscapeWidthLabel.setText(String.format("Width: %d%%", lw + 10));
            tabletLandscapeHeightSlider.setProgress(lh);
            tabletLandscapeHeightLabel.setText(String.format("Height: %d%%", lh + 10));
        } else {
            urlInput.setText(DEFAULT_URL);
            // Phone card height default 68%
            phoneCardHeightSlider.setProgress(58);
            phoneCardHeightLabel.setText("Height: 68%");
            // Tablet defaults to match iOS (40%, 50%, 30%, 60%)
            tabletPortraitWidthSlider.setProgress(30);
            tabletPortraitWidthLabel.setText("Width: 40%");
            tabletPortraitHeightSlider.setProgress(40);
            tabletPortraitHeightLabel.setText("Height: 50%");
            tabletLandscapeWidthSlider.setProgress(20);
            tabletLandscapeWidthLabel.setText("Width: 30%");
            tabletLandscapeHeightSlider.setProgress(50);
            tabletLandscapeHeightLabel.setText("Height: 60%");
        }
        
        // Set initial advanced options visibility
        updateAdvancedOptionsVisibility();
        
        // Advanced options toggle
        advancedOptionsToggle.setOnClickListener(v -> {
            isAdvancedExpanded = !isAdvancedExpanded;
            updateAdvancedOptionsVisibility();
        });
        
        // Initialize StashPayCard
        StashPayCard stashPayCard = StashPayCard.getInstance();
        stashPayCard.setActivity(this);
        
        // Apply initial sizing from sliders
        stashPayCard.setCardHeightRatioPortrait((phoneCardHeightSlider.getProgress() + 10) / 100f);
        stashPayCard.setTabletWidthRatioPortrait((tabletPortraitWidthSlider.getProgress() + 10) / 100f);
        stashPayCard.setTabletHeightRatioPortrait((tabletPortraitHeightSlider.getProgress() + 10) / 100f);
        stashPayCard.setTabletWidthRatioLandscape((tabletLandscapeWidthSlider.getProgress() + 10) / 100f);
        stashPayCard.setTabletHeightRatioLandscape((tabletLandscapeHeightSlider.getProgress() + 10) / 100f);
        
        // Web View Mode toggle
        webViewModeSwitch.setOnCheckedChangeListener((buttonView, isChecked) -> {
            stashPayCard.setForceWebBasedCheckout(isChecked);
            String modeText = isChecked ? "Web View (Chrome)" : "Card UI";
            statusText.setText("Mode: " + modeText);
        });
        
        // Landscape Lock toggle
        SwitchMaterial landscapeLockSwitch = findViewById(R.id.landscapeLockSwitch);
        landscapeLockSwitch.setOnCheckedChangeListener((buttonView, isChecked) -> {
            if (isChecked) {
                setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
                statusText.setText("Locked to Landscape");
            } else {
                setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
                statusText.setText("Orientation Unlocked");
            }
        });
        
        // Phone Card Height Slider (10% to 100%)
        phoneCardHeightSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                float ratio = (progress + 10) / 100f;
                phoneCardHeightLabel.setText(String.format("Height: %d%%", progress + 10));
                stashPayCard.setCardHeightRatioPortrait(ratio);
            }
            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        
        // Tablet Portrait Width Slider (10% to 100%)
        tabletPortraitWidthSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                float ratio = (progress + 10) / 100f;
                tabletPortraitWidthLabel.setText(String.format("Width: %d%%", progress + 10));
                stashPayCard.setTabletWidthRatioPortrait(ratio);
            }
            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        
        // Tablet Portrait Height Slider (10% to 100%)
        tabletPortraitHeightSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                float ratio = (progress + 10) / 100f;
                tabletPortraitHeightLabel.setText(String.format("Height: %d%%", progress + 10));
                stashPayCard.setTabletHeightRatioPortrait(ratio);
            }
            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        
        // Tablet Landscape Width Slider (10% to 100%)
        tabletLandscapeWidthSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                float ratio = (progress + 10) / 100f;
                tabletLandscapeWidthLabel.setText(String.format("Width: %d%%", progress + 10));
                stashPayCard.setTabletWidthRatioLandscape(ratio);
            }
            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        
        // Tablet Landscape Height Slider (10% to 100%)
        tabletLandscapeHeightSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                float ratio = (progress + 10) / 100f;
                tabletLandscapeHeightLabel.setText(String.format("Height: %d%%", progress + 10));
                stashPayCard.setTabletHeightRatioLandscape(ratio);
            }
            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        
        // Set up event listener
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
                runOnUiThread(() -> {
                    statusText.setText("Dialog dismissed");
                });
            }
            
            @Override
            public void onOptInResponse(String optinType) {
                Log.i(TAG, "Opt-in response: " + optinType);
                runOnUiThread(() -> {
                    statusText.setText("Opt-in: " + optinType);
                });
            }
            
            @Override
            public void onPageLoaded(long loadTimeMs) {
                Log.i(TAG, "Page loaded in " + loadTimeMs + "ms");
            }
        });
        
        // Open Checkout (Card UI)
        openCheckoutButton.setOnClickListener(v -> {
            String url = urlInput.getText().toString().trim();
            if (!url.isEmpty()) {
                statusText.setText("Opening checkout...");
                stashPayCard.openCheckout(url);
            } else {
                Toast.makeText(this, "Please enter a URL", Toast.LENGTH_SHORT).show();
            }
        });
    }
    
    @Override
    protected void onResume() {
        super.onResume();
        // Update activity reference in case it changed
        StashPayCard.getInstance().setActivity(this);
    }
    
    @Override
    protected void onSaveInstanceState(@NonNull Bundle outState) {
        super.onSaveInstanceState(outState);
        // Save state for configuration changes
        outState.putString(KEY_URL, urlInput.getText().toString());
        outState.putBoolean(KEY_ADVANCED_EXPANDED, isAdvancedExpanded);
        outState.putInt(KEY_PHONE_CARD_HEIGHT, phoneCardHeightSlider.getProgress());
        outState.putInt(KEY_TABLET_PORTRAIT_WIDTH, tabletPortraitWidthSlider.getProgress());
        outState.putInt(KEY_TABLET_PORTRAIT_HEIGHT, tabletPortraitHeightSlider.getProgress());
        outState.putInt(KEY_TABLET_LANDSCAPE_WIDTH, tabletLandscapeWidthSlider.getProgress());
        outState.putInt(KEY_TABLET_LANDSCAPE_HEIGHT, tabletLandscapeHeightSlider.getProgress());
    }
    
    /**
     * Updates the visibility and indicator of the advanced options section.
     */
    private void updateAdvancedOptionsVisibility() {
        if (isAdvancedExpanded) {
            advancedOptionsContainer.setVisibility(View.VISIBLE);
            advancedOptionsToggle.setText("▼ Advanced Options");
        } else {
            advancedOptionsContainer.setVisibility(View.GONE);
            advancedOptionsToggle.setText("▶ Advanced Options");
        }
    }
}
