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

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.switchmaterial.SwitchMaterial;

import com.stash.popup.StashPayCard;

/**
 * Sample activity demonstrating StashPayCard SDK integration.
 */
public class MainActivity extends AppCompatActivity {
    private static final String TAG = "StashNativeDemo";
    
    private static final String DEFAULT_URL = "https://htmlpreview.github.io/?https://raw.githubusercontent.com/stashgg/stash-unity/refs/heads/main/.github/Stash.Popup.Test/index.html";
    
    private EditText urlInput;
    private TextView statusText;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        urlInput = findViewById(R.id.urlInput);
        statusText = findViewById(R.id.statusText);
        Button openCheckoutButton = findViewById(R.id.openCheckoutButton);
        SwitchMaterial webViewModeSwitch = findViewById(R.id.webViewModeSwitch);
        
        // Size configuration UI
        TextView phoneHeightLabel = findViewById(R.id.phoneHeightLabel);
        SeekBar phoneHeightSlider = findViewById(R.id.phoneHeightSlider);
        TextView tabletWidthLabel = findViewById(R.id.tabletWidthLabel);
        SeekBar tabletWidthSlider = findViewById(R.id.tabletWidthSlider);
        TextView tabletHeightLabel = findViewById(R.id.tabletHeightLabel);
        SeekBar tabletHeightSlider = findViewById(R.id.tabletHeightSlider);
        
        urlInput.setText(DEFAULT_URL);
        
        // Initialize StashPayCard
        StashPayCard stashPayCard = StashPayCard.getInstance();
        stashPayCard.setActivity(this);
        
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
        
        // Phone Height Slider (10% to 100%)
        phoneHeightSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                float ratio = (progress + 10) / 100f; // 10% to 100%
                phoneHeightLabel.setText(String.format("Phone Height: %d%%", progress + 10));
                stashPayCard.setCardHeightRatio(ratio);
            }
            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        
        // Tablet Width Slider (10% to 100%)
        tabletWidthSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                float ratio = (progress + 10) / 100f; // 10% to 100%
                tabletWidthLabel.setText(String.format("Tablet Width: %d%%", progress + 10));
                stashPayCard.setTabletWidthRatio(ratio);
            }
            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        
        // Tablet Height Slider (10% to 100%)
        tabletHeightSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                float ratio = (progress + 10) / 100f; // 10% to 100%
                tabletHeightLabel.setText(String.format("Tablet Height: %d%%", progress + 10));
                stashPayCard.setTabletHeightRatio(ratio);
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
}
