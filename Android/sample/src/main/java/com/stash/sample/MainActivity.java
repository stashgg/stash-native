package com.stash.sample;

import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import com.stash.popup.StashPayCard;

/**
 * Sample activity demonstrating StashPayCard SDK integration.
 */
public class MainActivity extends AppCompatActivity {
    private static final String TAG = "StashPaySample";
    
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
        Button openPopupButton = findViewById(R.id.openPopupButton);
        
        urlInput.setText(DEFAULT_URL);
        
        // Initialize StashPayCard
        StashPayCard stashPayCard = StashPayCard.getInstance();
        stashPayCard.setActivity(this);
        
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
        
        // Open Popup
        openPopupButton.setOnClickListener(v -> {
            String url = urlInput.getText().toString().trim();
            if (!url.isEmpty()) {
                statusText.setText("Opening popup...");
                stashPayCard.openPopup(url);
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
