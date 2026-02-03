package com.stash.nativedemo;

import android.content.Context;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.SeekBar;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.materialswitch.MaterialSwitch;
import com.google.android.material.textfield.TextInputEditText;
import com.stash.nativedemo.databinding.ItemHeaderBinding;
import com.stash.nativedemo.databinding.ItemSectionHeaderBinding;
import com.stash.nativedemo.databinding.ItemSectionFooterBinding;
import com.stash.nativedemo.databinding.ItemPreferenceUrlBinding;
import com.stash.nativedemo.databinding.ItemPreferenceActionBinding;
import com.stash.nativedemo.databinding.ItemExpandableHeaderBinding;
import com.stash.nativedemo.databinding.ItemPreferenceSwitchBinding;
import com.stash.nativedemo.databinding.ItemPreferenceSliderBinding;

import java.util.ArrayList;
import java.util.List;

/**
 * RecyclerView adapter for the settings-style list (Google Settings pattern).
 * Uses ViewBinding and multiple view types.
 */
public class SettingsAdapter extends RecyclerView.Adapter<RecyclerView.ViewHolder> {

    private List<SettingsItem> items = new ArrayList<>();
    private final MainViewModel viewModel;
    private final Callbacks callbacks;

    public interface Callbacks {
        void onOpenCheckout();
        void onOpenModal();
        void onGenerateCheckout();
    }

    public SettingsAdapter(MainViewModel viewModel, Callbacks callbacks) {
        this.viewModel = viewModel;
        this.callbacks = callbacks;
    }

    public void submitList(List<SettingsItem> newItems) {
        this.items = newItems != null ? newItems : new ArrayList<>();
        notifyDataSetChanged();
    }

    @Override
    public int getItemViewType(int position) {
        return items.get(position).type;
    }

    @NonNull
    @Override
    public RecyclerView.ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        LayoutInflater inflater = LayoutInflater.from(parent.getContext());
        switch (viewType) {
            case SettingsItem.TYPE_HEADER:
                return new HeaderVH(ItemHeaderBinding.inflate(inflater, parent, false));
            case SettingsItem.TYPE_SECTION_HEADER:
                return new SectionHeaderVH(ItemSectionHeaderBinding.inflate(inflater, parent, false));
            case SettingsItem.TYPE_SECTION_FOOTER:
                return new SectionFooterVH(ItemSectionFooterBinding.inflate(inflater, parent, false));
            case SettingsItem.TYPE_URL_PREFERENCE:
                return new UrlPreferenceVH(ItemPreferenceUrlBinding.inflate(inflater, parent, false));
            case SettingsItem.TYPE_ACTION_PREFERENCE:
                return new ActionPreferenceVH(ItemPreferenceActionBinding.inflate(inflater, parent, false));
            case SettingsItem.TYPE_EXPANDABLE_HEADER:
                return new ExpandableHeaderVH(ItemExpandableHeaderBinding.inflate(inflater, parent, false));
            case SettingsItem.TYPE_SWITCH_PREFERENCE:
                return new SwitchPreferenceVH(ItemPreferenceSwitchBinding.inflate(inflater, parent, false));
            case SettingsItem.TYPE_SLIDER_PREFERENCE:
                return new SliderPreferenceVH(ItemPreferenceSliderBinding.inflate(inflater, parent, false));
            default:
                throw new IllegalArgumentException("Unknown type " + viewType);
        }
    }

    @Override
    public void onBindViewHolder(@NonNull RecyclerView.ViewHolder holder, int position) {
        SettingsItem item = items.get(position);
        switch (item.type) {
            case SettingsItem.TYPE_HEADER:
                ((HeaderVH) holder).bind(item);
                break;
            case SettingsItem.TYPE_SECTION_HEADER:
                ((SectionHeaderVH) holder).bind(item);
                break;
            case SettingsItem.TYPE_SECTION_FOOTER:
                ((SectionFooterVH) holder).bind(item);
                break;
            case SettingsItem.TYPE_URL_PREFERENCE:
                ((UrlPreferenceVH) holder).bind(item, position);
                break;
            case SettingsItem.TYPE_ACTION_PREFERENCE:
                ((ActionPreferenceVH) holder).bind(item, position);
                break;
            case SettingsItem.TYPE_EXPANDABLE_HEADER:
                ((ExpandableHeaderVH) holder).bind(item);
                break;
            case SettingsItem.TYPE_SWITCH_PREFERENCE:
                ((SwitchPreferenceVH) holder).bind(item, position);
                break;
            case SettingsItem.TYPE_SLIDER_PREFERENCE:
                ((SliderPreferenceVH) holder).bind(item, position);
                break;
        }
        applyCardStyle(holder.itemView, item);
    }

    private static final int CARD_MARGIN_HORIZONTAL_DP = 16;
    private static final int CARD_MARGIN_TOP_DP = 12;
    private static final int CARD_MARGIN_BOTTOM_DP = 12;

    private void applyCardStyle(View itemView, SettingsItem item) {
        if (item.type == SettingsItem.TYPE_HEADER) {
            itemView.setBackground(null);
            return;
        }
        Context ctx = itemView.getContext();
        float density = ctx.getResources().getDisplayMetrics().density;
        int horizontal = Math.round(CARD_MARGIN_HORIZONTAL_DP * density);
        int top = Math.round(CARD_MARGIN_TOP_DP * density);
        int bottom = Math.round(CARD_MARGIN_BOTTOM_DP * density);

        boolean first = item.firstInCard;
        boolean last = item.lastInCard;

        if (first && last) {
            itemView.setBackgroundResource(R.drawable.bg_card_single);
            setMargins(itemView, horizontal, top, horizontal, bottom);
        } else if (first) {
            itemView.setBackgroundResource(R.drawable.bg_card_top);
            setMargins(itemView, horizontal, top, horizontal, 0);
        } else if (last) {
            itemView.setBackgroundResource(R.drawable.bg_card_bottom);
            setMargins(itemView, horizontal, 0, horizontal, bottom);
        } else {
            itemView.setBackgroundResource(R.drawable.bg_card_middle);
            setMargins(itemView, horizontal, 0, horizontal, 0);
        }
    }

    private void setMargins(View v, int left, int top, int right, int bottom) {
        ViewGroup.MarginLayoutParams lp = (ViewGroup.MarginLayoutParams) v.getLayoutParams();
        if (lp != null) {
            lp.leftMargin = left;
            lp.topMargin = top;
            lp.rightMargin = right;
            lp.bottomMargin = bottom;
            v.setLayoutParams(lp);
        }
    }

    @Override
    public int getItemCount() {
        return items.size();
    }

    private int findActionPosition(int position) {
        for (int i = 0; i < position; i++) {
            SettingsItem it = items.get(i);
            if (it.type == SettingsItem.TYPE_ACTION_PREFERENCE) {
                int titleRes = it.titleRes;
                if (titleRes == R.string.open_checkout) return 0;
                if (titleRes == R.string.open_modal) return 1;
                if (titleRes == R.string.generate_checkout) return 2;
            }
        }
        return -1;
    }

    private int findSwitchOrSliderPosition(int position) {
        int switchIndex = 0;
        for (int i = 0; i < position; i++) {
            SettingsItem it = items.get(i);
            if (it.type == SettingsItem.TYPE_SWITCH_PREFERENCE || it.type == SettingsItem.TYPE_SLIDER_PREFERENCE) {
                switchIndex++;
            }
        }
        return switchIndex;
    }

    static class HeaderVH extends RecyclerView.ViewHolder {
        private final ItemHeaderBinding b;

        HeaderVH(ItemHeaderBinding b) {
            super(b.getRoot());
            this.b = b;
        }

        void bind(SettingsItem item) {
            b.headerTitle.setText(item.titleRes);
            b.headerSubtitle.setText(item.supportingRes);
        }
    }

    static class SectionHeaderVH extends RecyclerView.ViewHolder {
        private final ItemSectionHeaderBinding b;

        SectionHeaderVH(ItemSectionHeaderBinding b) {
            super(b.getRoot());
            this.b = b;
        }

        void bind(SettingsItem item) {
            b.sectionHeaderText.setText(item.titleRes);
        }
    }

    static class SectionFooterVH extends RecyclerView.ViewHolder {
        private final ItemSectionFooterBinding b;

        SectionFooterVH(ItemSectionFooterBinding b) {
            super(b.getRoot());
            this.b = b;
        }

        void bind(SettingsItem item) {
            b.sectionFooterText.setText(item.titleRes);
        }
    }

    class UrlPreferenceVH extends RecyclerView.ViewHolder {
        private final ItemPreferenceUrlBinding b;
        private int boundPosition = -1;

        UrlPreferenceVH(ItemPreferenceUrlBinding b) {
            super(b.getRoot());
            this.b = b;
        }

        private int boundTitleRes;

        void bind(SettingsItem item, int position) {
            boundPosition = position;
            boundTitleRes = item.titleRes;
            b.preferenceIcon.setImageResource(item.iconRes);
            b.urlInputLayout.setHint(item.titleRes);
            b.urlEditText.removeTextChangedListener(watcher);
            b.urlEditText.setText(item.value);
            b.urlEditText.addTextChangedListener(watcher);
        }

        private final TextWatcher watcher = new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {}

            @Override
            public void afterTextChanged(Editable s) {
                String text = s != null ? s.toString() : "";
                if (boundTitleRes == R.string.hint_checkout_url) {
                    viewModel.setCheckoutUrl(text);
                } else if (boundTitleRes == R.string.hint_modal_url) {
                    viewModel.setModalUrl(text);
                } else if (boundTitleRes == R.string.hint_api_key) {
                    viewModel.setStashApiKey(text);
                }
            }
        };
    }

    class ActionPreferenceVH extends RecyclerView.ViewHolder {
        private final ItemPreferenceActionBinding b;

        ActionPreferenceVH(ItemPreferenceActionBinding b) {
            super(b.getRoot());
            this.b = b;
        }

        void bind(SettingsItem item, int position) {
            b.actionIcon.setImageResource(item.iconRes);
            b.actionTitle.setText(item.titleRes);
            b.actionRow.setOnClickListener(v -> {
                if (item.titleRes == R.string.open_checkout) {
                    callbacks.onOpenCheckout();
                } else if (item.titleRes == R.string.open_modal) {
                    callbacks.onOpenModal();
                } else if (item.titleRes == R.string.generate_checkout) {
                    callbacks.onGenerateCheckout();
                }
            });
        }
    }

    class ExpandableHeaderVH extends RecyclerView.ViewHolder {
        private final ItemExpandableHeaderBinding b;

        ExpandableHeaderVH(ItemExpandableHeaderBinding b) {
            super(b.getRoot());
            this.b = b;
        }

        void bind(SettingsItem item) {
            b.expandableIcon.setImageResource(item.iconRes);
            b.expandableTitle.setText(item.titleRes);
            b.expandableChevron.setRotation(item.expanded ? 90f : 0f);
            b.expandableRow.setOnClickListener(v -> {
                v.post(() -> {
                    if (item.titleRes == R.string.show_checkout_options || item.titleRes == R.string.hide_checkout_options) {
                        viewModel.toggleCheckoutOptions();
                    } else if (item.titleRes == R.string.show_modal_options || item.titleRes == R.string.hide_modal_options) {
                        viewModel.toggleModalOptions();
                    }
                });
            });
        }
    }

    class SwitchPreferenceVH extends RecyclerView.ViewHolder {
        private final ItemPreferenceSwitchBinding b;

        SwitchPreferenceVH(ItemPreferenceSwitchBinding b) {
            super(b.getRoot());
            this.b = b;
        }

        void bind(SettingsItem item, int position) {
            b.switchTitle.setText(item.titleRes);
            if (item.supportingRes != 0) {
                b.switchSupporting.setText(item.supportingRes);
                b.switchSupporting.setVisibility(View.VISIBLE);
            } else {
                b.switchSupporting.setVisibility(View.GONE);
            }
            b.switchPreference.setOnCheckedChangeListener(null);
            b.switchPreference.setChecked(item.checked);
            b.switchPreference.setOnCheckedChangeListener((buttonView, isChecked) -> {
                if (item.titleRes == R.string.option_web_view_mode) {
                    viewModel.setWebViewMode(isChecked);
                } else if (item.titleRes == R.string.option_force_portrait_on_checkout) {
                    viewModel.setForcePortraitOnCheckout(isChecked);
                } else if (item.titleRes == R.string.option_show_drag_bar) {
                    viewModel.setModalShowDragBar(isChecked);
                } else if (item.titleRes == R.string.option_allow_dismiss) {
                    viewModel.setModalAllowDismiss(isChecked);
                } else if (item.titleRes == R.string.option_use_test_api) {
                    viewModel.setUseTestApi(isChecked);
                }
            });
        }
    }

    class SliderPreferenceVH extends RecyclerView.ViewHolder {
        private final ItemPreferenceSliderBinding b;

        SliderPreferenceVH(ItemPreferenceSliderBinding b) {
            super(b.getRoot());
            this.b = b;
        }

        void bind(SettingsItem item, int position) {
            b.sliderTitle.setText(item.titleRes);
            b.sliderValue.setText(item.value);
            b.sliderSeekBar.setProgress(item.progress);
            b.sliderSeekBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
                @Override
                public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                    if (!fromUser) return;
                    int titleRes = item.titleRes;
                    if (titleRes == R.string.phone_card_height) viewModel.setPhoneCardHeight(progress);
                    else if (titleRes == R.string.checkout_phone_landscape_width) viewModel.setCheckoutPhoneLandscapeWidth(progress);
                    else if (titleRes == R.string.checkout_phone_landscape_height) viewModel.setCheckoutPhoneLandscapeHeight(progress);
                    else if (titleRes == R.string.tablet_portrait_width) viewModel.setCheckoutTabletPortraitWidth(progress);
                    else if (titleRes == R.string.tablet_portrait_height) viewModel.setCheckoutTabletPortraitHeight(progress);
                    else if (titleRes == R.string.tablet_landscape_width) viewModel.setCheckoutTabletLandscapeWidth(progress);
                    else if (titleRes == R.string.tablet_landscape_height) viewModel.setCheckoutTabletLandscapeHeight(progress);
                    else if (titleRes == R.string.phone_portrait_width) viewModel.setModalPhonePortraitWidth(progress);
                    else if (titleRes == R.string.phone_portrait_height) viewModel.setModalPhonePortraitHeight(progress);
                    else if (titleRes == R.string.phone_landscape_width) viewModel.setModalPhoneLandscapeWidth(progress);
                    else if (titleRes == R.string.phone_landscape_height) viewModel.setModalPhoneLandscapeHeight(progress);
                    else if (titleRes == R.string.tablet_portrait_width_modal) viewModel.setModalTabletPortraitWidth(progress);
                    else if (titleRes == R.string.tablet_portrait_height_modal) viewModel.setModalTabletPortraitHeight(progress);
                    else if (titleRes == R.string.tablet_landscape_width_modal) viewModel.setModalTabletLandscapeWidth(progress);
                    else if (titleRes == R.string.tablet_landscape_height_modal) viewModel.setModalTabletLandscapeHeight(progress);
                }
                @Override
                public void onStartTrackingTouch(SeekBar seekBar) {}
                @Override
                public void onStopTrackingTouch(SeekBar seekBar) {}
            });
        }
    }
}
