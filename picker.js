// Working preview of the Mojito picker.
//
// - Runs an idle animation until the user clicks/types into the input.
// - Once the user takes over, the input drives a live fuzzy search against
//   the embedded shortcode list. Arrow keys + Enter + Esc behave like the
//   real app (PickerView.swift).
// - Picker follows the `:` horizontally as text is typed before it.

(function () {
  const inputs = Array.from(document.querySelectorAll('.demo-input'));
  const carousel = document.getElementById('carousel');
  const picker = document.getElementById('picker');
  const list = document.getElementById('picker-list');
  if (!inputs.length || !carousel || !picker || !list) return;

  // `input` is the currently active textarea. Updated when the carousel
  // advances or the user clicks into a different app's input.
  let input = inputs[0];
  const apps = Array.from(document.querySelectorAll('.app'));
  // Small horizontal drift on enter/exit; opacity does the heavy lifting.
  const SLIDE = 60;

  // Window corners use CSS border-radius (14px). We previously approximated
  // a real macOS squircle with a clip-path superellipse, but clip-path
  // breaks box-shadow + border, so the windows rendered with no rim and
  // no drop shadow on the real page. At 14px the CSS rounded corner is
  // visually indistinguishable from the true squircle anyway.

  function transformAt(x) {
    return `translate(-50%, -50%) translateX(${x}px)`;
  }

  // Read once at script load; the autoplay loop, wait(), and setActiveApp all
  // honor this so reduced-motion users don't see the carousel slide-in or
  // typing animation.
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let currentAppIdx = -1;

  // Every transition fades + drifts right-to-left: outgoing fades out drifting
  // left, incoming snaps to the right at opacity 0 then fades in drifting to
  // center. The fade carries most of the perceived motion; SLIDE just hints
  // direction so the wrap (last → first) still reads as "next".
  function setActiveApp(idx) {
    if (idx === currentAppIdx) return;
    const prev = currentAppIdx;
    apps.forEach((app, i) => {
      if (i === idx) {
        if (reduceMotion) {
          app.style.transition = 'none';
          app.style.transform = transformAt(0);
          app.style.opacity = '1';
          app.classList.add('is-active');
        } else {
          // Snap to the right at opacity 0, then fade + drift to center.
          app.style.transition = 'none';
          app.style.transform = transformAt(SLIDE);
          app.style.opacity = '0';
          // Force the snap to commit before the animation starts.
          void app.offsetWidth;
          requestAnimationFrame(() => {
            app.style.transition = '';
            app.style.transform = transformAt(0);
            app.style.opacity = '1';
            app.classList.add('is-active');
          });
        }
      } else if (i === prev) {
        if (reduceMotion) {
          app.style.transition = 'none';
          app.style.transform = transformAt(-SLIDE);
          app.style.opacity = '0';
        } else {
          app.style.transition = '';
          app.style.transform = transformAt(-SLIDE);
          app.style.opacity = '0';
        }
        app.classList.remove('is-active');
      }
      // Other apps: leave wherever they were (already faded out).
    });
    currentAppIdx = idx;
    input = inputs[idx];
    cachedFont = ''; // each app may use a different font (terminal is monospace)
  }

  const DB = [
    ["regional_indicator_a","🇦"],
    ["regional_indicator_b","🇧"],
    ["regional_indicator_c","🇨"],
    ["regional_indicator_d","🇩"],
    ["regional_indicator_e","🇪"],
    ["regional_indicator_f","🇫"],
    ["regional_indicator_g","🇬"],
    ["regional_indicator_h","🇭"],
    ["regional_indicator_i","🇮"],
    ["regional_indicator_j","🇯"],
    ["regional_indicator_k","🇰"],
    ["regional_indicator_l","🇱"],
    ["regional_indicator_m","🇲"],
    ["regional_indicator_n","🇳"],
    ["regional_indicator_o","🇴"],
    ["regional_indicator_p","🇵"],
    ["regional_indicator_q","🇶"],
    ["regional_indicator_r","🇷"],
    ["regional_indicator_s","🇸"],
    ["regional_indicator_t","🇹"],
    ["regional_indicator_u","🇺"],
    ["regional_indicator_v","🇻"],
    ["regional_indicator_w","🇼"],
    ["regional_indicator_x","🇽"],
    ["regional_indicator_y","🇾"],
    ["regional_indicator_z","🇿"],
    ["grinning","😀"],
    ["grinning_face","😀"],
    ["smiley","😃"],
    ["grinning_face_with_big_eyes","😃"],
    ["smile","😄"],
    ["grinning_face_with_closed_eyes","😄"],
    ["grin","😁"],
    ["beaming_face","😁"],
    ["laughing","😆"],
    ["satisfied","😆"],
    ["lol","😆"],
    ["squinting_face","😆"],
    ["sweat_smile","😅"],
    ["grinning_face_with_sweat","😅"],
    ["rolling_on_the_floor_laughing","🤣"],
    ["rofl","🤣"],
    ["joy","😂"],
    ["lmao","😂"],
    ["tears_of_joy","😂"],
    ["slightly_smiling_face","🙂"],
    ["upside_down_face","🙃"],
    ["melting_face","🫠"],
    ["melt","🫠"],
    ["wink","😉"],
    ["winking_face","😉"],
    ["blush","😊"],
    ["smiling_face_with_closed_eyes","😊"],
    ["innocent","😇"],
    ["halo","😇"],
    ["smiling_face_with_3_hearts","🥰"],
    ["smiling_face_with_three_hearts","🥰"],
    ["heart_eyes","😍"],
    ["smiling_face_with_heart_eyes","😍"],
    ["star-struck","🤩"],
    ["grinning_face_with_star_eyes","🤩"],
    ["star_struck","🤩"],
    ["kissing_heart","😘"],
    ["blowing_a_kiss","😘"],
    ["kissing","😗"],
    ["kissing_face","😗"],
    ["relaxed","☺️"],
    ["smiling_face","☺️"],
    ["kissing_closed_eyes","😚"],
    ["kissing_face_with_closed_eyes","😚"],
    ["kissing_smiling_eyes","😙"],
    ["kissing_face_with_smiling_eyes","😙"],
    ["smiling_face_with_tear","🥲"],
    ["yum","😋"],
    ["savoring_food","😋"],
    ["stuck_out_tongue","😛"],
    ["face_with_tongue","😛"],
    ["stuck_out_tongue_winking_eye","😜"],
    ["zany_face","🤪"],
    ["grinning_face_with_one_large_and_one_small_eye","🤪"],
    ["zany","🤪"],
    ["stuck_out_tongue_closed_eyes","😝"],
    ["money_mouth_face","🤑"],
    ["hugging_face","🤗"],
    ["hugs","🤗"],
    ["hug","🤗"],
    ["hugging","🤗"],
    ["face_with_hand_over_mouth","🤭"],
    ["smiling_face_with_smiling_eyes_and_hand_covering_mouth","🤭"],
    ["hand_over_mouth","🤭"],
    ["face_with_open_eyes_and_hand_over_mouth","🫢"],
    ["face_with_open_eyes_hand_over_mouth","🫢"],
    ["gasp","🫢"],
    ["face_with_peeking_eye","🫣"],
    ["peek","🫣"],
    ["shushing_face","🤫"],
    ["face_with_finger_covering_closed_lips","🤫"],
    ["shush","🤫"],
    ["thinking_face","🤔"],
    ["thinking","🤔"],
    ["wtf","🤔"],
    ["saluting_face","🫡"],
    ["salute","🫡"],
    ["zipper_mouth_face","🤐"],
    ["zipper_mouth","🤐"],
    ["face_with_raised_eyebrow","🤨"],
    ["face_with_one_eyebrow_raised","🤨"],
    ["raised_eyebrow","🤨"],
    ["neutral_face","😐️"],
    ["neutral","😐️"],
    ["expressionless","😑"],
    ["expressionless_face","😑"],
    ["no_mouth","😶"],
    ["dotted_line_face","🫥"],
    ["face_in_clouds","😶‍🌫️"],
    ["in_clouds","😶‍🌫️"],
    ["smirk","😏"],
    ["smirking","😏"],
    ["smirking_face","😏"],
    ["unamused","😒"],
    ["unamused_face","😒"],
    ["face_with_rolling_eyes","🙄"],
    ["roll_eyes","🙄"],
    ["rolling_eyes","🙄"],
    ["grimacing","😬"],
    ["grimacing_face","😬"],
    ["face_exhaling","😮‍💨"],
    ["exhale","😮‍💨"],
    ["exhaling","😮‍💨"],
    ["lying_face","🤥"],
    ["lying","🤥"],
    ["shaking_face","🫨"],
    ["shaking","🫨"],
    ["head_shaking_horizontally","🙂‍↔️"],
    ["head_shaking_vertically","🙂‍↕️"],
    ["relieved","😌"],
    ["relieved_face","😌"],
    ["pensive","😔"],
    ["pensive_face","😔"],
    ["sleepy","😪"],
    ["sleepy_face","😪"],
    ["drooling_face","🤤"],
    ["drooling","🤤"],
    ["sleeping","😴"],
    ["sleeping_face","😴"],
    ["face_with_bags_under_eyes","🫩"],
    ["face_with_eye_bags","🫩"],
    ["mask","😷"],
    ["medical_mask","😷"],
    ["face_with_thermometer","🤒"],
    ["face_with_head_bandage","🤕"],
    ["nauseated_face","🤢"],
    ["nauseated","🤢"],
    ["face_vomiting","🤮"],
    ["face_with_open_mouth_vomiting","🤮"],
    ["vomiting_face","🤮"],
    ["vomiting","🤮"],
    ["sneezing_face","🤧"],
    ["sneezing","🤧"],
    ["hot_face","🥵"],
    ["hot","🥵"],
    ["cold_face","🥶"],
    ["cold","🥶"],
    ["woozy_face","🥴"],
    ["woozy","🥴"],
    ["dizzy_face","😵"],
    ["knocked_out","😵"],
    ["face_with_spiral_eyes","😵‍💫"],
    ["dizzy_eyes","😵‍💫"],
    ["exploding_head","🤯"],
    ["shocked_face_with_exploding_head","🤯"],
    ["face_with_cowboy_hat","🤠"],
    ["cowboy_hat_face","🤠"],
    ["cowboy","🤠"],
    ["cowboy_face","🤠"],
    ["partying_face","🥳"],
    ["hooray","🥳"],
    ["partying","🥳"],
    ["disguised_face","🥸"],
    ["disguised","🥸"],
    ["sunglasses","😎"],
    ["smiling_face_with_sunglasses","😎"],
    ["sunglasses_cool","😎"],
    ["too_cool","😎"],
    ["nerd_face","🤓"],
    ["nerd","🤓"],
    ["face_with_monocle","🧐"],
    ["monocle_face","🧐"],
    ["confused","😕"],
    ["confused_face","😕"],
    ["face_with_diagonal_mouth","🫤"],
    ["worried","😟"],
    ["worried_face","😟"],
    ["slightly_frowning_face","🙁"],
    ["white_frowning_face","☹️"],
    ["frowning_face","☹️"],
    ["open_mouth","😮"],
    ["face_with_open_mouth","😮"],
    ["hushed","😯"],
    ["hushed_face","😯"],
    ["astonished","😲"],
    ["astonished_face","😲"],
    ["flushed","😳"],
    ["flushed_face","😳"],
    ["distorted_face","🫪"],
    ["pleading_face","🥺"],
    ["pleading","🥺"],
    ["face_holding_back_tears","🥹"],
    ["watery_eyes","🥹"],
    ["frowning","😦"],
    ["frowning_face","😦"],
    ["anguished","😧"],
    ["anguished_face","😧"],
    ["fearful","😨"],
    ["fearful_face","😨"],
    ["cold_sweat","😰"],
    ["anxious","😰"],
    ["anxious_face","😰"],
    ["disappointed_relieved","😥"],
    ["sad_relieved_face","😥"],
    ["cry","😢"],
    ["crying_face","😢"],
    ["sob","😭"],
    ["loudly_crying_face","😭"],
    ["scream","😱"],
    ["screaming_in_fear","😱"],
    ["confounded","😖"],
    ["confounded_face","😖"],
    ["persevere","😣"],
    ["persevering_face","😣"],
    ["disappointed","😞"],
    ["disappointed_face","😞"],
    ["sweat","😓"],
    ["downcast_face","😓"],
    ["weary","😩"],
    ["weary_face","😩"],
    ["tired_face","😫"],
    ["tired","😫"],
    ["yawning_face","🥱"],
    ["yawn","🥱"],
    ["yawning","🥱"],
    ["triumph","😤"],
    ["nose_steam","😤"],
    ["rage","😡"],
    ["pout","😡"],
    ["pouting_face","😡"],
    ["angry","😠"],
    ["angry_face","😠"],
    ["face_with_symbols_on_mouth","🤬"],
    ["serious_face_with_symbols_covering_mouth","🤬"],
    ["cursing_face","🤬"],
    ["censored","🤬"],
    ["smiling_imp","😈"],
    ["imp","👿"],
    ["angry_imp","👿"],
    ["skull","💀"],
    ["skull_and_crossbones","☠️"],
    ["hankey","💩"],
    ["poop","💩"],
    ["shit","💩"],
    ["clown_face","🤡"],
    ["clown","🤡"],
    ["japanese_ogre","👹"],
    ["ogre","👹"],
    ["japanese_goblin","👺"],
    ["goblin","👺"],
    ["ghost","👻"],
    ["alien","👽️"],
    ["space_invader","👾"],
    ["alien_monster","👾"],
    ["robot_face","🤖"],
    ["robot","🤖"],
    ["smiley_cat","😺"],
    ["grinning_cat","😺"],
    ["smile_cat","😸"],
    ["grinning_cat_with_closed_eyes","😸"],
    ["joy_cat","😹"],
    ["tears_of_joy_cat","😹"],
    ["heart_eyes_cat","😻"],
    ["smiling_cat_with_heart_eyes","😻"],
    ["smirk_cat","😼"],
    ["wry_smile_cat","😼"],
    ["kissing_cat","😽"],
    ["scream_cat","🙀"],
    ["weary_cat","🙀"],
    ["crying_cat_face","😿"],
    ["crying_cat","😿"],
    ["pouting_cat","😾"],
    ["see_no_evil","🙈"],
    ["hear_no_evil","🙉"],
    ["speak_no_evil","🙊"],
    ["love_letter","💌"],
    ["cupid","💘"],
    ["heart_with_arrow","💘"],
    ["gift_heart","💝"],
    ["heart_with_ribbon","💝"],
    ["sparkling_heart","💖"],
    ["heartpulse","💗"],
    ["growing_heart","💗"],
    ["heartbeat","💓"],
    ["beating_heart","💓"],
    ["revolving_hearts","💞"],
    ["two_hearts","💕"],
    ["heart_decoration","💟"],
    ["heavy_heart_exclamation_mark_ornament","❣️"],
    ["heavy_heart_exclamation","❣️"],
    ["heart_exclamation","❣️"],
    ["broken_heart","💔"],
    ["heart_on_fire","❤️‍🔥"],
    ["mending_heart","❤️‍🩹"],
    ["heart","❤️"],
    ["red_heart","❤️"],
    ["pink_heart","🩷"],
    ["orange_heart","🧡"],
    ["yellow_heart","💛"],
    ["green_heart","💚"],
    ["blue_heart","💙"],
    ["light_blue_heart","🩵"],
    ["purple_heart","💜"],
    ["brown_heart","🤎"],
    ["black_heart","🖤"],
    ["grey_heart","🩶"],
    ["gray_heart","🩶"],
    ["white_heart","🤍"],
    ["kiss","💋"],
    ["100","💯"],
    ["anger","💢"],
    ["fight_cloud","🫯"],
    ["boom","💥"],
    ["collision","💥"],
    ["dizzy","💫"],
    ["sweat_drops","💦"],
    ["dash","💨"],
    ["dashing_away","💨"],
    ["hole","🕳️"],
    ["speech_balloon","💬"],
    ["eye-in-speech-bubble","👁️‍🗨️"],
    ["eye_speech_bubble","👁️‍🗨️"],
    ["eye_in_speech_bubble","👁️‍🗨️"],
    ["left_speech_bubble","🗨️"],
    ["right_anger_bubble","🗯️"],
    ["thought_balloon","💭"],
    ["zzz","💤"],
    ["wave","👋"],
    ["waving_hand","👋"],
    ["raised_back_of_hand","🤚"],
    ["raised_hand_with_fingers_splayed","🖐️"],
    ["hand","✋️"],
    ["raised_hand","✋️"],
    ["high_five","✋️"],
    ["spock-hand","🖖"],
    ["vulcan_salute","🖖"],
    ["vulcan","🖖"],
    ["rightwards_hand","🫱"],
    ["leftwards_hand","🫲"],
    ["palm_down_hand","🫳"],
    ["palm_down","🫳"],
    ["palm_up_hand","🫴"],
    ["palm_up","🫴"],
    ["leftwards_pushing_hand","🫷"],
    ["rightwards_pushing_hand","🫸"],
    ["ok_hand","👌"],
    ["pinched_fingers","🤌"],
    ["pinch","🤌"],
    ["pinching_hand","🤏"],
    ["v","✌️"],
    ["victory","✌️"],
    ["crossed_fingers","🤞"],
    ["hand_with_index_and_middle_fingers_crossed","🤞"],
    ["fingers_crossed","🤞"],
    ["hand_with_index_finger_and_thumb_crossed","🫰"],
    ["i_love_you_hand_sign","🤟"],
    ["love_you_gesture","🤟"],
    ["the_horns","🤘"],
    ["sign_of_the_horns","🤘"],
    ["metal","🤘"],
    ["call_me_hand","🤙"],
    ["point_left","👈️"],
    ["point_right","👉️"],
    ["point_up_2","👆️"],
    ["point_up","👆️"],
    ["middle_finger","🖕"],
    ["reversed_hand_with_middle_finger_extended","🖕"],
    ["fu","🖕"],
    ["point_down","👇️"],
    ["point_up","☝️"],
    ["point_up_2","☝️"],
    ["index_pointing_at_the_viewer","🫵"],
    ["point_forward","🫵"],
    ["+1","👍️"],
    ["thumbsup","👍️"],
    ["yes","👍️"],
    ["-1","👎️"],
    ["thumbsdown","👎️"],
    ["no","👎️"],
    ["fist","✊️"],
    ["fist_raised","✊️"],
    ["facepunch","👊"],
    ["punch","👊"],
    ["fist_oncoming","👊"],
    ["left-facing_fist","🤛"],
    ["fist_left","🤛"],
    ["left_facing_fist","🤛"],
    ["right-facing_fist","🤜"],
    ["fist_right","🤜"],
    ["right_facing_fist","🤜"],
    ["clap","👏"],
    ["clapping_hands","👏"],
    ["raised_hands","🙌"],
    ["heart_hands","🫶"],
    ["open_hands","👐"],
    ["palms_up_together","🤲"],
    ["handshake","🤝"],
    ["pray","🙏"],
    ["folded_hands","🙏"],
    ["writing_hand","✍️"],
    ["nail_care","💅"],
    ["nail_polish","💅"],
    ["selfie","🤳"],
    ["muscle","💪"],
    ["right_bicep","💪"],
    ["mechanical_arm","🦾"],
    ["mechanical_leg","🦿"],
    ["leg","🦵"],
    ["foot","🦶"],
    ["ear","👂️"],
    ["ear_with_hearing_aid","🦻"],
    ["hearing_aid","🦻"],
    ["nose","👃"],
    ["brain","🧠"],
    ["anatomical_heart","🫀"],
    ["lungs","🫁"],
    ["tooth","🦷"],
    ["bone","🦴"],
    ["eyes","👀"],
    ["eye","👁️"],
    ["tongue","👅"],
    ["lips","👄"],
    ["mouth","👄"],
    ["biting_lip","🫦"],
    ["baby","👶"],
    ["child","🧒"],
    ["boy","👦"],
    ["girl","👧"],
    ["adult","🧑"],
    ["person_with_blond_hair","👱"],
    ["blond_haired_person","👱"],
    ["blond_haired","👱"],
    ["man","👨"],
    ["bearded_person","🧔"],
    ["person_bearded","🧔"],
    ["man_with_beard","🧔‍♂️"],
    ["man_beard","🧔‍♂️"],
    ["man_bearded","🧔‍♂️"],
    ["woman_with_beard","🧔‍♀️"],
    ["woman_beard","🧔‍♀️"],
    ["woman_bearded","🧔‍♀️"],
    ["red_haired_man","👨‍🦰"],
    ["man_red_haired","👨‍🦰"],
    ["curly_haired_man","👨‍🦱"],
    ["man_curly_haired","👨‍🦱"],
    ["white_haired_man","👨‍🦳"],
    ["man_white_haired","👨‍🦳"],
    ["bald_man","👨‍🦲"],
    ["man_bald","👨‍🦲"],
    ["woman","👩"],
    ["red_haired_woman","👩‍🦰"],
    ["woman_red_haired","👩‍🦰"],
    ["red_haired_person","🧑‍🦰"],
    ["person_red_hair","🧑‍🦰"],
    ["red_haired","🧑‍🦰"],
    ["curly_haired_woman","👩‍🦱"],
    ["woman_curly_haired","👩‍🦱"],
    ["curly_haired_person","🧑‍🦱"],
    ["person_curly_hair","🧑‍🦱"],
    ["curly_haired","🧑‍🦱"],
    ["white_haired_woman","👩‍🦳"],
    ["woman_white_haired","👩‍🦳"],
    ["white_haired_person","🧑‍🦳"],
    ["person_white_hair","🧑‍🦳"],
    ["white_haired","🧑‍🦳"],
    ["bald_woman","👩‍🦲"],
    ["woman_bald","👩‍🦲"],
    ["bald_person","🧑‍🦲"],
    ["person_bald","🧑‍🦲"],
    ["bald","🧑‍🦲"],
    ["blond-haired-woman","👱‍♀️"],
    ["blond_haired_woman","👱‍♀️"],
    ["blonde_woman","👱‍♀️"],
    ["woman_blond_haired","👱‍♀️"],
    ["blond-haired-man","👱‍♂️"],
    ["blond_haired_man","👱‍♂️"],
    ["man_blond_haired","👱‍♂️"],
    ["older_adult","🧓"],
    ["older_man","👴"],
    ["older_woman","👵"],
    ["person_frowning","🙍"],
    ["frowning_person","🙍"],
    ["man-frowning","🙍‍♂️"],
    ["frowning_man","🙍‍♂️"],
    ["man_frowning","🙍‍♂️"],
    ["woman-frowning","🙍‍♀️"],
    ["frowning_woman","🙍‍♀️"],
    ["woman_frowning","🙍‍♀️"],
    ["person_with_pouting_face","🙎"],
    ["pouting_face","🙎"],
    ["person_pouting","🙎"],
    ["pouting","🙎"],
    ["man-pouting","🙎‍♂️"],
    ["pouting_man","🙎‍♂️"],
    ["man_pouting","🙎‍♂️"],
    ["woman-pouting","🙎‍♀️"],
    ["pouting_woman","🙎‍♀️"],
    ["woman_pouting","🙎‍♀️"],
    ["no_good","🙅"],
    ["person_gesturing_no","🙅"],
    ["man-gesturing-no","🙅‍♂️"],
    ["ng_man","🙅‍♂️"],
    ["no_good_man","🙅‍♂️"],
    ["man_gesturing_no","🙅‍♂️"],
    ["woman-gesturing-no","🙅‍♀️"],
    ["ng_woman","🙅‍♀️"],
    ["no_good_woman","🙅‍♀️"],
    ["woman_gesturing_no","🙅‍♀️"],
    ["ok_woman","🙆"],
    ["ok_person","🙆"],
    ["all_good","🙆"],
    ["person_gesturing_ok","🙆"],
    ["man-gesturing-ok","🙆‍♂️"],
    ["ok_man","🙆‍♂️"],
    ["man_gesturing_ok","🙆‍♂️"],
    ["woman-gesturing-ok","🙆‍♀️"],
    ["ok_woman","🙆‍♀️"],
    ["woman_gesturing_ok","🙆‍♀️"],
    ["information_desk_person","💁"],
    ["tipping_hand_person","💁"],
    ["person_tipping_hand","💁"],
    ["man-tipping-hand","💁‍♂️"],
    ["sassy_man","💁‍♂️"],
    ["tipping_hand_man","💁‍♂️"],
    ["man_tipping_hand","💁‍♂️"],
    ["woman-tipping-hand","💁‍♀️"],
    ["sassy_woman","💁‍♀️"],
    ["tipping_hand_woman","💁‍♀️"],
    ["woman_tipping_hand","💁‍♀️"],
    ["raising_hand","🙋"],
    ["person_raising_hand","🙋"],
    ["man-raising-hand","🙋‍♂️"],
    ["raising_hand_man","🙋‍♂️"],
    ["man_raising_hand","🙋‍♂️"],
    ["woman-raising-hand","🙋‍♀️"],
    ["raising_hand_woman","🙋‍♀️"],
    ["woman_raising_hand","🙋‍♀️"],
    ["deaf_person","🧏"],
    ["deaf_man","🧏‍♂️"],
    ["deaf_woman","🧏‍♀️"],
    ["bow","🙇"],
    ["person_bowing","🙇"],
    ["man-bowing","🙇‍♂️"],
    ["bowing_man","🙇‍♂️"],
    ["man_bowing","🙇‍♂️"],
    ["woman-bowing","🙇‍♀️"],
    ["bowing_woman","🙇‍♀️"],
    ["woman_bowing","🙇‍♀️"],
    ["face_palm","🤦"],
    ["facepalm","🤦"],
    ["person_facepalming","🤦"],
    ["man-facepalming","🤦‍♂️"],
    ["man_facepalming","🤦‍♂️"],
    ["woman-facepalming","🤦‍♀️"],
    ["woman_facepalming","🤦‍♀️"],
    ["shrug","🤷"],
    ["person_shrugging","🤷"],
    ["man-shrugging","🤷‍♂️"],
    ["man_shrugging","🤷‍♂️"],
    ["woman-shrugging","🤷‍♀️"],
    ["woman_shrugging","🤷‍♀️"],
    ["health_worker","🧑‍⚕️"],
    ["male-doctor","👨‍⚕️"],
    ["man_health_worker","👨‍⚕️"],
    ["female-doctor","👩‍⚕️"],
    ["woman_health_worker","👩‍⚕️"],
    ["student","🧑‍🎓"],
    ["male-student","👨‍🎓"],
    ["man_student","👨‍🎓"],
    ["female-student","👩‍🎓"],
    ["woman_student","👩‍🎓"],
    ["teacher","🧑‍🏫"],
    ["male-teacher","👨‍🏫"],
    ["man_teacher","👨‍🏫"],
    ["female-teacher","👩‍🏫"],
    ["woman_teacher","👩‍🏫"],
    ["judge","🧑‍⚖️"],
    ["male-judge","👨‍⚖️"],
    ["man_judge","👨‍⚖️"],
    ["female-judge","👩‍⚖️"],
    ["woman_judge","👩‍⚖️"],
    ["farmer","🧑‍🌾"],
    ["male-farmer","👨‍🌾"],
    ["man_farmer","👨‍🌾"],
    ["female-farmer","👩‍🌾"],
    ["woman_farmer","👩‍🌾"],
    ["cook","🧑‍🍳"],
    ["male-cook","👨‍🍳"],
    ["man_cook","👨‍🍳"],
    ["female-cook","👩‍🍳"],
    ["woman_cook","👩‍🍳"],
    ["mechanic","🧑‍🔧"],
    ["male-mechanic","👨‍🔧"],
    ["man_mechanic","👨‍🔧"],
    ["female-mechanic","👩‍🔧"],
    ["woman_mechanic","👩‍🔧"],
    ["factory_worker","🧑‍🏭"],
    ["male-factory-worker","👨‍🏭"],
    ["man_factory_worker","👨‍🏭"],
    ["female-factory-worker","👩‍🏭"],
    ["woman_factory_worker","👩‍🏭"],
    ["office_worker","🧑‍💼"],
    ["male-office-worker","👨‍💼"],
    ["man_office_worker","👨‍💼"],
    ["female-office-worker","👩‍💼"],
    ["woman_office_worker","👩‍💼"],
    ["scientist","🧑‍🔬"],
    ["male-scientist","👨‍🔬"],
    ["man_scientist","👨‍🔬"],
    ["female-scientist","👩‍🔬"],
    ["woman_scientist","👩‍🔬"],
    ["technologist","🧑‍💻"],
    ["male-technologist","👨‍💻"],
    ["man_technologist","👨‍💻"],
    ["female-technologist","👩‍💻"],
    ["woman_technologist","👩‍💻"],
    ["singer","🧑‍🎤"],
    ["male-singer","👨‍🎤"],
    ["man_singer","👨‍🎤"],
    ["female-singer","👩‍🎤"],
    ["woman_singer","👩‍🎤"],
    ["artist","🧑‍🎨"],
    ["male-artist","👨‍🎨"],
    ["man_artist","👨‍🎨"],
    ["female-artist","👩‍🎨"],
    ["woman_artist","👩‍🎨"],
    ["pilot","🧑‍✈️"],
    ["male-pilot","👨‍✈️"],
    ["man_pilot","👨‍✈️"],
    ["female-pilot","👩‍✈️"],
    ["woman_pilot","👩‍✈️"],
    ["astronaut","🧑‍🚀"],
    ["male-astronaut","👨‍🚀"],
    ["man_astronaut","👨‍🚀"],
    ["female-astronaut","👩‍🚀"],
    ["woman_astronaut","👩‍🚀"],
    ["firefighter","🧑‍🚒"],
    ["male-firefighter","👨‍🚒"],
    ["man_firefighter","👨‍🚒"],
    ["female-firefighter","👩‍🚒"],
    ["woman_firefighter","👩‍🚒"],
    ["cop","👮"],
    ["police_officer","👮"],
    ["male-police-officer","👮‍♂️"],
    ["policeman","👮‍♂️"],
    ["man_police_officer","👮‍♂️"],
    ["female-police-officer","👮‍♀️"],
    ["policewoman","👮‍♀️"],
    ["woman_police_officer","👮‍♀️"],
    ["sleuth_or_spy","🕵️"],
    ["detective","🕵️"],
    ["male-detective","🕵️‍♂️"],
    ["male_detective","🕵️‍♂️"],
    ["man_detective","🕵️‍♂️"],
    ["female-detective","🕵️‍♀️"],
    ["female_detective","🕵️‍♀️"],
    ["woman_detective","🕵️‍♀️"],
    ["guardsman","💂"],
    ["guard","💂"],
    ["male-guard","💂‍♂️"],
    ["guardsman","💂‍♂️"],
    ["man_guard","💂‍♂️"],
    ["female-guard","💂‍♀️"],
    ["guardswoman","💂‍♀️"],
    ["woman_guard","💂‍♀️"],
    ["ninja","🥷"],
    ["construction_worker","👷"],
    ["male-construction-worker","👷‍♂️"],
    ["construction_worker_man","👷‍♂️"],
    ["man_construction_worker","👷‍♂️"],
    ["female-construction-worker","👷‍♀️"],
    ["construction_worker_woman","👷‍♀️"],
    ["woman_construction_worker","👷‍♀️"],
    ["person_with_crown","🫅"],
    ["royalty","🫅"],
    ["prince","🤴"],
    ["princess","👸"],
    ["man_with_turban","👳"],
    ["person_with_turban","👳"],
    ["person_wearing_turban","👳"],
    ["man-wearing-turban","👳‍♂️"],
    ["man_with_turban","👳‍♂️"],
    ["man_wearing_turban","👳‍♂️"],
    ["woman-wearing-turban","👳‍♀️"],
    ["woman_with_turban","👳‍♀️"],
    ["woman_wearing_turban","👳‍♀️"],
    ["man_with_gua_pi_mao","👲"],
    ["person_with_skullcap","👲"],
    ["person_with_headscarf","🧕"],
    ["woman_with_headscarf","🧕"],
    ["person_in_tuxedo","🤵"],
    ["man_in_tuxedo","🤵‍♂️"],
    ["woman_in_tuxedo","🤵‍♀️"],
    ["bride_with_veil","👰"],
    ["person_with_veil","👰"],
    ["man_with_veil","👰‍♂️"],
    ["woman_with_veil","👰‍♀️"],
    ["bride_with_veil","👰‍♀️"],
    ["pregnant_woman","🤰"],
    ["pregnant_man","🫃"],
    ["pregnant_person","🫄"],
    ["breast-feeding","🤱"],
    ["breast_feeding","🤱"],
    ["woman_feeding_baby","👩‍🍼"],
    ["man_feeding_baby","👨‍🍼"],
    ["person_feeding_baby","🧑‍🍼"],
    ["angel","👼"],
    ["santa","🎅"],
    ["mrs_claus","🤶"],
    ["mother_christmas","🤶"],
    ["mx_claus","🧑‍🎄"],
    ["superhero","🦸"],
    ["male_superhero","🦸‍♂️"],
    ["superhero_man","🦸‍♂️"],
    ["man_superhero","🦸‍♂️"],
    ["female_superhero","🦸‍♀️"],
    ["superhero_woman","🦸‍♀️"],
    ["woman_superhero","🦸‍♀️"],
    ["supervillain","🦹"],
    ["male_supervillain","🦹‍♂️"],
    ["supervillain_man","🦹‍♂️"],
    ["man_supervillain","🦹‍♂️"],
    ["female_supervillain","🦹‍♀️"],
    ["supervillain_woman","🦹‍♀️"],
    ["woman_supervillain","🦹‍♀️"],
    ["mage","🧙"],
    ["male_mage","🧙‍♂️"],
    ["mage_man","🧙‍♂️"],
    ["man_mage","🧙‍♂️"],
    ["female_mage","🧙‍♀️"],
    ["mage_woman","🧙‍♀️"],
    ["woman_mage","🧙‍♀️"],
    ["fairy","🧚"],
    ["male_fairy","🧚‍♂️"],
    ["fairy_man","🧚‍♂️"],
    ["man_fairy","🧚‍♂️"],
    ["female_fairy","🧚‍♀️"],
    ["fairy_woman","🧚‍♀️"],
    ["woman_fairy","🧚‍♀️"],
    ["vampire","🧛"],
    ["male_vampire","🧛‍♂️"],
    ["vampire_man","🧛‍♂️"],
    ["man_vampire","🧛‍♂️"],
    ["female_vampire","🧛‍♀️"],
    ["vampire_woman","🧛‍♀️"],
    ["woman_vampire","🧛‍♀️"],
    ["merperson","🧜"],
    ["merman","🧜‍♂️"],
    ["mermaid","🧜‍♀️"],
    ["elf","🧝"],
    ["male_elf","🧝‍♂️"],
    ["elf_man","🧝‍♂️"],
    ["man_elf","🧝‍♂️"],
    ["female_elf","🧝‍♀️"],
    ["elf_woman","🧝‍♀️"],
    ["woman_elf","🧝‍♀️"],
    ["genie","🧞"],
    ["male_genie","🧞‍♂️"],
    ["genie_man","🧞‍♂️"],
    ["man_genie","🧞‍♂️"],
    ["female_genie","🧞‍♀️"],
    ["genie_woman","🧞‍♀️"],
    ["woman_genie","🧞‍♀️"],
    ["zombie","🧟"],
    ["male_zombie","🧟‍♂️"],
    ["zombie_man","🧟‍♂️"],
    ["man_zombie","🧟‍♂️"],
    ["female_zombie","🧟‍♀️"],
    ["zombie_woman","🧟‍♀️"],
    ["woman_zombie","🧟‍♀️"],
    ["troll","🧌"],
    ["hairy_creature","🫈"],
    ["massage","💆"],
    ["person_getting_massage","💆"],
    ["man-getting-massage","💆‍♂️"],
    ["massage_man","💆‍♂️"],
    ["man_getting_massage","💆‍♂️"],
    ["woman-getting-massage","💆‍♀️"],
    ["massage_woman","💆‍♀️"],
    ["woman_getting_massage","💆‍♀️"],
    ["haircut","💇"],
    ["person_getting_haircut","💇"],
    ["man-getting-haircut","💇‍♂️"],
    ["haircut_man","💇‍♂️"],
    ["man_getting_haircut","💇‍♂️"],
    ["woman-getting-haircut","💇‍♀️"],
    ["haircut_woman","💇‍♀️"],
    ["woman_getting_haircut","💇‍♀️"],
    ["walking","🚶"],
    ["person_walking","🚶"],
    ["man-walking","🚶‍♂️"],
    ["walking_man","🚶‍♂️"],
    ["man_walking","🚶‍♂️"],
    ["woman-walking","🚶‍♀️"],
    ["walking_woman","🚶‍♀️"],
    ["woman_walking","🚶‍♀️"],
    ["person_walking_facing_right","🚶‍➡️"],
    ["person_walking_right","🚶‍➡️"],
    ["woman_walking_facing_right","🚶‍♀️‍➡️"],
    ["woman_walking_right","🚶‍♀️‍➡️"],
    ["man_walking_facing_right","🚶‍♂️‍➡️"],
    ["man_walking_right","🚶‍♂️‍➡️"],
    ["standing_person","🧍"],
    ["person_standing","🧍"],
    ["standing","🧍"],
    ["man_standing","🧍‍♂️"],
    ["standing_man","🧍‍♂️"],
    ["woman_standing","🧍‍♀️"],
    ["standing_woman","🧍‍♀️"],
    ["kneeling_person","🧎"],
    ["kneeling","🧎"],
    ["person_kneeling","🧎"],
    ["man_kneeling","🧎‍♂️"],
    ["kneeling_man","🧎‍♂️"],
    ["woman_kneeling","🧎‍♀️"],
    ["kneeling_woman","🧎‍♀️"],
    ["person_kneeling_facing_right","🧎‍➡️"],
    ["person_kneeling_right","🧎‍➡️"],
    ["woman_kneeling_facing_right","🧎‍♀️‍➡️"],
    ["woman_kneeling_right","🧎‍♀️‍➡️"],
    ["man_kneeling_facing_right","🧎‍♂️‍➡️"],
    ["man_kneeling_right","🧎‍♂️‍➡️"],
    ["person_with_probing_cane","🧑‍🦯"],
    ["person_with_white_cane","🧑‍🦯"],
    ["person_with_white_cane_facing_right","🧑‍🦯‍➡️"],
    ["person_with_white_cane_right","🧑‍🦯‍➡️"],
    ["man_with_probing_cane","👨‍🦯"],
    ["man_with_white_cane","👨‍🦯"],
    ["man_with_white_cane_facing_right","👨‍🦯‍➡️"],
    ["man_with_white_cane_right","👨‍🦯‍➡️"],
    ["woman_with_probing_cane","👩‍🦯"],
    ["woman_with_white_cane","👩‍🦯"],
    ["woman_with_white_cane_facing_right","👩‍🦯‍➡️"],
    ["woman_with_white_cane_right","👩‍🦯‍➡️"],
    ["person_in_motorized_wheelchair","🧑‍🦼"],
    ["person_in_motorized_wheelchair_facing_right","🧑‍🦼‍➡️"],
    ["person_in_motorized_wheelchair_right","🧑‍🦼‍➡️"],
    ["man_in_motorized_wheelchair","👨‍🦼"],
    ["man_in_motorized_wheelchair_facing_right","👨‍🦼‍➡️"],
    ["man_in_motorized_wheelchair_right","👨‍🦼‍➡️"],
    ["woman_in_motorized_wheelchair","👩‍🦼"],
    ["woman_in_motorized_wheelchair_facing_right","👩‍🦼‍➡️"],
    ["woman_in_motorized_wheelchair_right","👩‍🦼‍➡️"],
    ["person_in_manual_wheelchair","🧑‍🦽"],
    ["person_in_manual_wheelchair_facing_right","🧑‍🦽‍➡️"],
    ["person_in_manual_wheelchair_right","🧑‍🦽‍➡️"],
    ["man_in_manual_wheelchair","👨‍🦽"],
    ["man_in_manual_wheelchair_facing_right","👨‍🦽‍➡️"],
    ["man_in_manual_wheelchair_right","👨‍🦽‍➡️"],
    ["woman_in_manual_wheelchair","👩‍🦽"],
    ["woman_in_manual_wheelchair_facing_right","👩‍🦽‍➡️"],
    ["woman_in_manual_wheelchair_right","👩‍🦽‍➡️"],
    ["runner","🏃"],
    ["running","🏃"],
    ["person_running","🏃"],
    ["man-running","🏃‍♂️"],
    ["running_man","🏃‍♂️"],
    ["man_running","🏃‍♂️"],
    ["woman-running","🏃‍♀️"],
    ["running_woman","🏃‍♀️"],
    ["woman_running","🏃‍♀️"],
    ["person_running_facing_right","🏃‍➡️"],
    ["person_running_right","🏃‍➡️"],
    ["woman_running_facing_right","🏃‍♀️‍➡️"],
    ["woman_running_right","🏃‍♀️‍➡️"],
    ["man_running_facing_right","🏃‍♂️‍➡️"],
    ["man_running_right","🏃‍♂️‍➡️"],
    ["ballet_dancer","🧑‍🩰"],
    ["dancer","💃"],
    ["woman_dancing","💃"],
    ["man_dancing","🕺"],
    ["man_in_business_suit_levitating","🕴️"],
    ["business_suit_levitating","🕴️"],
    ["levitate","🕴️"],
    ["levitating","🕴️"],
    ["person_in_suit_levitating","🕴️"],
    ["dancers","👯"],
    ["people_with_bunny_ears_partying","👯"],
    ["men-with-bunny-ears-partying","👯‍♂️"],
    ["man-with-bunny-ears-partying","👯‍♂️"],
    ["dancing_men","👯‍♂️"],
    ["men_with_bunny_ears_partying","👯‍♂️"],
    ["women-with-bunny-ears-partying","👯‍♀️"],
    ["woman-with-bunny-ears-partying","👯‍♀️"],
    ["dancing_women","👯‍♀️"],
    ["women_with_bunny_ears_partying","👯‍♀️"],
    ["person_in_steamy_room","🧖"],
    ["sauna_person","🧖"],
    ["man_in_steamy_room","🧖‍♂️"],
    ["sauna_man","🧖‍♂️"],
    ["woman_in_steamy_room","🧖‍♀️"],
    ["sauna_woman","🧖‍♀️"],
    ["person_climbing","🧗"],
    ["climbing","🧗"],
    ["man_climbing","🧗‍♂️"],
    ["climbing_man","🧗‍♂️"],
    ["woman_climbing","🧗‍♀️"],
    ["climbing_woman","🧗‍♀️"],
    ["fencer","🤺"],
    ["person_fencing","🤺"],
    ["fencing","🤺"],
    ["horse_racing","🏇"],
    ["skier","⛷️"],
    ["person_skiing","⛷️"],
    ["skiing","⛷️"],
    ["snowboarder","🏂️"],
    ["person_snowboarding","🏂️"],
    ["snowboarding","🏂️"],
    ["golfer","🏌️"],
    ["golfing","🏌️"],
    ["person_golfing","🏌️"],
    ["man-golfing","🏌️‍♂️"],
    ["golfing_man","🏌️‍♂️"],
    ["man_golfing","🏌️‍♂️"],
    ["woman-golfing","🏌️‍♀️"],
    ["golfing_woman","🏌️‍♀️"],
    ["woman_golfing","🏌️‍♀️"],
    ["surfer","🏄️"],
    ["person_surfing","🏄️"],
    ["surfing","🏄️"],
    ["man-surfing","🏄‍♂️"],
    ["surfing_man","🏄‍♂️"],
    ["man_surfing","🏄‍♂️"],
    ["woman-surfing","🏄‍♀️"],
    ["surfing_woman","🏄‍♀️"],
    ["woman_surfing","🏄‍♀️"],
    ["rowboat","🚣"],
    ["person_rowing_boat","🚣"],
    ["man-rowing-boat","🚣‍♂️"],
    ["rowing_man","🚣‍♂️"],
    ["man_rowing_boat","🚣‍♂️"],
    ["woman-rowing-boat","🚣‍♀️"],
    ["rowing_woman","🚣‍♀️"],
    ["woman_rowing_boat","🚣‍♀️"],
    ["swimmer","🏊️"],
    ["person_swimming","🏊️"],
    ["swimming","🏊️"],
    ["man-swimming","🏊‍♂️"],
    ["swimming_man","🏊‍♂️"],
    ["man_swimming","🏊‍♂️"],
    ["woman-swimming","🏊‍♀️"],
    ["swimming_woman","🏊‍♀️"],
    ["woman_swimming","🏊‍♀️"],
    ["person_with_ball","⛹️"],
    ["bouncing_ball_person","⛹️"],
    ["person_bouncing_ball","⛹️"],
    ["man-bouncing-ball","⛹️‍♂️"],
    ["basketball_man","⛹️‍♂️"],
    ["bouncing_ball_man","⛹️‍♂️"],
    ["man_bouncing_ball","⛹️‍♂️"],
    ["woman-bouncing-ball","⛹️‍♀️"],
    ["basketball_woman","⛹️‍♀️"],
    ["bouncing_ball_woman","⛹️‍♀️"],
    ["woman_bouncing_ball","⛹️‍♀️"],
    ["weight_lifter","🏋️"],
    ["weight_lifting","🏋️"],
    ["person_lifting_weights","🏋️"],
    ["man-lifting-weights","🏋️‍♂️"],
    ["weight_lifting_man","🏋️‍♂️"],
    ["man_lifting_weights","🏋️‍♂️"],
    ["woman-lifting-weights","🏋️‍♀️"],
    ["weight_lifting_woman","🏋️‍♀️"],
    ["woman_lifting_weights","🏋️‍♀️"],
    ["bicyclist","🚴"],
    ["biking","🚴"],
    ["person_biking","🚴"],
    ["man-biking","🚴‍♂️"],
    ["biking_man","🚴‍♂️"],
    ["man_biking","🚴‍♂️"],
    ["woman-biking","🚴‍♀️"],
    ["biking_woman","🚴‍♀️"],
    ["woman_biking","🚴‍♀️"],
    ["mountain_bicyclist","🚵"],
    ["mountain_biking","🚵"],
    ["person_mountain_biking","🚵"],
    ["man-mountain-biking","🚵‍♂️"],
    ["mountain_biking_man","🚵‍♂️"],
    ["man_mountain_biking","🚵‍♂️"],
    ["woman-mountain-biking","🚵‍♀️"],
    ["mountain_biking_woman","🚵‍♀️"],
    ["woman_mountain_biking","🚵‍♀️"],
    ["person_doing_cartwheel","🤸"],
    ["cartwheeling","🤸"],
    ["person_cartwheel","🤸"],
    ["man-cartwheeling","🤸‍♂️"],
    ["man_cartwheeling","🤸‍♂️"],
    ["woman-cartwheeling","🤸‍♀️"],
    ["woman_cartwheeling","🤸‍♀️"],
    ["wrestlers","🤼"],
    ["wrestling","🤼"],
    ["people_wrestling","🤼"],
    ["man-wrestling","🤼‍♂️"],
    ["men_wrestling","🤼‍♂️"],
    ["woman-wrestling","🤼‍♀️"],
    ["women_wrestling","🤼‍♀️"],
    ["water_polo","🤽"],
    ["person_playing_water_polo","🤽"],
    ["man-playing-water-polo","🤽‍♂️"],
    ["man_playing_water_polo","🤽‍♂️"],
    ["woman-playing-water-polo","🤽‍♀️"],
    ["woman_playing_water_polo","🤽‍♀️"],
    ["handball","🤾"],
    ["handball_person","🤾"],
    ["person_playing_handball","🤾"],
    ["man-playing-handball","🤾‍♂️"],
    ["man_playing_handball","🤾‍♂️"],
    ["woman-playing-handball","🤾‍♀️"],
    ["woman_playing_handball","🤾‍♀️"],
    ["juggling","🤹"],
    ["juggling_person","🤹"],
    ["juggler","🤹"],
    ["person_juggling","🤹"],
    ["man-juggling","🤹‍♂️"],
    ["man_juggling","🤹‍♂️"],
    ["woman-juggling","🤹‍♀️"],
    ["woman_juggling","🤹‍♀️"],
    ["person_in_lotus_position","🧘"],
    ["lotus_position","🧘"],
    ["man_in_lotus_position","🧘‍♂️"],
    ["lotus_position_man","🧘‍♂️"],
    ["woman_in_lotus_position","🧘‍♀️"],
    ["lotus_position_woman","🧘‍♀️"],
    ["bath","🛀"],
    ["person_taking_bath","🛀"],
    ["sleeping_accommodation","🛌"],
    ["sleeping_bed","🛌"],
    ["person_in_bed","🛌"],
    ["people_holding_hands","🧑‍🤝‍🧑"],
    ["two_women_holding_hands","👭"],
    ["women_holding_hands","👭"],
    ["man_and_woman_holding_hands","👫"],
    ["woman_and_man_holding_hands","👫"],
    ["couple","👫"],
    ["two_men_holding_hands","👬"],
    ["men_holding_hands","👬"],
    ["couplekiss","💏"],
    ["couple_kiss","💏"],
    ["woman-kiss-man","👩‍❤️‍💋‍👨"],
    ["couplekiss_man_woman","👩‍❤️‍💋‍👨"],
    ["kiss_mw","👩‍❤️‍💋‍👨"],
    ["kiss_wm","👩‍❤️‍💋‍👨"],
    ["man-kiss-man","👨‍❤️‍💋‍👨"],
    ["couplekiss_man_man","👨‍❤️‍💋‍👨"],
    ["kiss_mm","👨‍❤️‍💋‍👨"],
    ["woman-kiss-woman","👩‍❤️‍💋‍👩"],
    ["couplekiss_woman_woman","👩‍❤️‍💋‍👩"],
    ["kiss_ww","👩‍❤️‍💋‍👩"],
    ["couple_with_heart","💑"],
    ["woman-heart-man","👩‍❤️‍👨"],
    ["couple_with_heart_woman_man","👩‍❤️‍👨"],
    ["couple_with_heart_mw","👩‍❤️‍👨"],
    ["couple_with_heart_wm","👩‍❤️‍👨"],
    ["man-heart-man","👨‍❤️‍👨"],
    ["couple_with_heart_man_man","👨‍❤️‍👨"],
    ["couple_with_heart_mm","👨‍❤️‍👨"],
    ["woman-heart-woman","👩‍❤️‍👩"],
    ["couple_with_heart_woman_woman","👩‍❤️‍👩"],
    ["couple_with_heart_ww","👩‍❤️‍👩"],
    ["man-woman-boy","👨‍👩‍👦"],
    ["family_man_woman_boy","👨‍👩‍👦"],
    ["family_mwb","👨‍👩‍👦"],
    ["man-woman-girl","👨‍👩‍👧"],
    ["family_man_woman_girl","👨‍👩‍👧"],
    ["family_mwg","👨‍👩‍👧"],
    ["man-woman-girl-boy","👨‍👩‍👧‍👦"],
    ["family_man_woman_girl_boy","👨‍👩‍👧‍👦"],
    ["family_mwgb","👨‍👩‍👧‍👦"],
    ["man-woman-boy-boy","👨‍👩‍👦‍👦"],
    ["family_man_woman_boy_boy","👨‍👩‍👦‍👦"],
    ["family_mwbb","👨‍👩‍👦‍👦"],
    ["man-woman-girl-girl","👨‍👩‍👧‍👧"],
    ["family_man_woman_girl_girl","👨‍👩‍👧‍👧"],
    ["family_mwgg","👨‍👩‍👧‍👧"],
    ["man-man-boy","👨‍👨‍👦"],
    ["family_man_man_boy","👨‍👨‍👦"],
    ["family_mmb","👨‍👨‍👦"],
    ["man-man-girl","👨‍👨‍👧"],
    ["family_man_man_girl","👨‍👨‍👧"],
    ["family_mmg","👨‍👨‍👧"],
    ["man-man-girl-boy","👨‍👨‍👧‍👦"],
    ["family_man_man_girl_boy","👨‍👨‍👧‍👦"],
    ["family_mmgb","👨‍👨‍👧‍👦"],
    ["man-man-boy-boy","👨‍👨‍👦‍👦"],
    ["family_man_man_boy_boy","👨‍👨‍👦‍👦"],
    ["family_mmbb","👨‍👨‍👦‍👦"],
    ["man-man-girl-girl","👨‍👨‍👧‍👧"],
    ["family_man_man_girl_girl","👨‍👨‍👧‍👧"],
    ["family_mmgg","👨‍👨‍👧‍👧"],
    ["woman-woman-boy","👩‍👩‍👦"],
    ["family_woman_woman_boy","👩‍👩‍👦"],
    ["family_wwb","👩‍👩‍👦"],
    ["woman-woman-girl","👩‍👩‍👧"],
    ["family_woman_woman_girl","👩‍👩‍👧"],
    ["family_wwg","👩‍👩‍👧"],
    ["woman-woman-girl-boy","👩‍👩‍👧‍👦"],
    ["family_woman_woman_girl_boy","👩‍👩‍👧‍👦"],
    ["family_wwgb","👩‍👩‍👧‍👦"],
    ["woman-woman-boy-boy","👩‍👩‍👦‍👦"],
    ["family_woman_woman_boy_boy","👩‍👩‍👦‍👦"],
    ["family_wwbb","👩‍👩‍👦‍👦"],
    ["woman-woman-girl-girl","👩‍👩‍👧‍👧"],
    ["family_woman_woman_girl_girl","👩‍👩‍👧‍👧"],
    ["family_wwgg","👩‍👩‍👧‍👧"],
    ["man-boy","👨‍👦"],
    ["family_man_boy","👨‍👦"],
    ["family_mb","👨‍👦"],
    ["man-boy-boy","👨‍👦‍👦"],
    ["family_man_boy_boy","👨‍👦‍👦"],
    ["family_mbb","👨‍👦‍👦"],
    ["man-girl","👨‍👧"],
    ["family_man_girl","👨‍👧"],
    ["family_mg","👨‍👧"],
    ["man-girl-boy","👨‍👧‍👦"],
    ["family_man_girl_boy","👨‍👧‍👦"],
    ["family_mgb","👨‍👧‍👦"],
    ["man-girl-girl","👨‍👧‍👧"],
    ["family_man_girl_girl","👨‍👧‍👧"],
    ["family_mgg","👨‍👧‍👧"],
    ["woman-boy","👩‍👦"],
    ["family_woman_boy","👩‍👦"],
    ["family_wb","👩‍👦"],
    ["woman-boy-boy","👩‍👦‍👦"],
    ["family_woman_boy_boy","👩‍👦‍👦"],
    ["family_wbb","👩‍👦‍👦"],
    ["woman-girl","👩‍👧"],
    ["family_woman_girl","👩‍👧"],
    ["family_wg","👩‍👧"],
    ["woman-girl-boy","👩‍👧‍👦"],
    ["family_woman_girl_boy","👩‍👧‍👦"],
    ["family_wgb","👩‍👧‍👦"],
    ["woman-girl-girl","👩‍👧‍👧"],
    ["family_woman_girl_girl","👩‍👧‍👧"],
    ["family_wgg","👩‍👧‍👧"],
    ["speaking_head_in_silhouette","🗣️"],
    ["speaking_head","🗣️"],
    ["bust_in_silhouette","👤"],
    ["busts_in_silhouette","👥"],
    ["people_hugging","🫂"],
    ["family","👪️"],
    ["family_adult_adult_child","🧑‍🧑‍🧒"],
    ["family_aac","🧑‍🧑‍🧒"],
    ["family_adult_adult_child_child","🧑‍🧑‍🧒‍🧒"],
    ["family_aacc","🧑‍🧑‍🧒‍🧒"],
    ["family_adult_child","🧑‍🧒"],
    ["family_aa","🧑‍🧒"],
    ["family_ac","🧑‍🧒"],
    ["family_adult_child_child","🧑‍🧒‍🧒"],
    ["family_acc","🧑‍🧒‍🧒"],
    ["footprints","👣"],
    ["fingerprint","🫆"],
    ["skin-tone-2","🏻"],
    ["tone1","🏻"],
    ["tone_light","🏻"],
    ["skin-tone-3","🏼"],
    ["tone2","🏼"],
    ["tone_medium_light","🏼"],
    ["skin-tone-4","🏽"],
    ["tone3","🏽"],
    ["tone_medium","🏽"],
    ["skin-tone-5","🏾"],
    ["tone4","🏾"],
    ["tone_medium_dark","🏾"],
    ["skin-tone-6","🏿"],
    ["tone5","🏿"],
    ["tone_dark","🏿"],
    ["red_hair","🦰"],
    ["curly_hair","🦱"],
    ["white_hair","🦳"],
    ["no_hair","🦲"],
    ["monkey_face","🐵"],
    ["monkey","🐒"],
    ["gorilla","🦍"],
    ["orangutan","🦧"],
    ["dog","🐶"],
    ["dog_face","🐶"],
    ["dog2","🐕️"],
    ["dog","🐕️"],
    ["guide_dog","🦮"],
    ["service_dog","🐕‍🦺"],
    ["poodle","🐩"],
    ["wolf","🐺"],
    ["wolf_face","🐺"],
    ["fox_face","🦊"],
    ["fox","🦊"],
    ["raccoon","🦝"],
    ["cat","🐱"],
    ["cat_face","🐱"],
    ["cat2","🐈️"],
    ["cat","🐈️"],
    ["black_cat","🐈‍⬛"],
    ["lion_face","🦁"],
    ["lion","🦁"],
    ["tiger","🐯"],
    ["tiger_face","🐯"],
    ["tiger2","🐅"],
    ["tiger","🐅"],
    ["leopard","🐆"],
    ["horse","🐴"],
    ["horse_face","🐴"],
    ["moose","🫎"],
    ["donkey","🫏"],
    ["racehorse","🐎"],
    ["horse","🐎"],
    ["unicorn_face","🦄"],
    ["unicorn","🦄"],
    ["zebra_face","🦓"],
    ["zebra","🦓"],
    ["deer","🦌"],
    ["bison","🦬"],
    ["cow","🐮"],
    ["cow_face","🐮"],
    ["ox","🐂"],
    ["water_buffalo","🐃"],
    ["cow2","🐄"],
    ["cow","🐄"],
    ["pig","🐷"],
    ["pig_face","🐷"],
    ["pig2","🐖"],
    ["pig","🐖"],
    ["boar","🐗"],
    ["pig_nose","🐽"],
    ["ram","🐏"],
    ["sheep","🐑"],
    ["ewe","🐑"],
    ["goat","🐐"],
    ["dromedary_camel","🐪"],
    ["camel","🐫"],
    ["llama","🦙"],
    ["giraffe_face","🦒"],
    ["giraffe","🦒"],
    ["elephant","🐘"],
    ["mammoth","🦣"],
    ["rhinoceros","🦏"],
    ["rhino","🦏"],
    ["hippopotamus","🦛"],
    ["hippo","🦛"],
    ["mouse","🐭"],
    ["mouse_face","🐭"],
    ["mouse2","🐁"],
    ["mouse","🐁"],
    ["rat","🐀"],
    ["hamster","🐹"],
    ["hamster_face","🐹"],
    ["rabbit","🐰"],
    ["rabbit_face","🐰"],
    ["rabbit2","🐇"],
    ["rabbit","🐇"],
    ["chipmunk","🐿️"],
    ["beaver","🦫"],
    ["hedgehog","🦔"],
    ["bat","🦇"],
    ["bear","🐻"],
    ["bear_face","🐻"],
    ["polar_bear","🐻‍❄️"],
    ["polar_bear_face","🐻‍❄️"],
    ["koala","🐨"],
    ["koala_face","🐨"],
    ["panda_face","🐼"],
    ["panda","🐼"],
    ["sloth","🦥"],
    ["otter","🦦"],
    ["skunk","🦨"],
    ["kangaroo","🦘"],
    ["badger","🦡"],
    ["feet","🐾"],
    ["paw_prints","🐾"],
    ["turkey","🦃"],
    ["chicken","🐔"],
    ["chicken_face","🐔"],
    ["rooster","🐓"],
    ["hatching_chick","🐣"],
    ["baby_chick","🐤"],
    ["hatched_chick","🐥"],
    ["bird","🐦️"],
    ["bird_face","🐦️"],
    ["penguin","🐧"],
    ["penguin_face","🐧"],
    ["dove_of_peace","🕊️"],
    ["dove","🕊️"],
    ["eagle","🦅"],
    ["duck","🦆"],
    ["swan","🦢"],
    ["owl","🦉"],
    ["dodo","🦤"],
    ["feather","🪶"],
    ["flamingo","🦩"],
    ["peacock","🦚"],
    ["parrot","🦜"],
    ["wing","🪽"],
    ["black_bird","🐦‍⬛"],
    ["goose","🪿"],
    ["phoenix","🐦‍🔥"],
    ["frog","🐸"],
    ["frog_face","🐸"],
    ["crocodile","🐊"],
    ["turtle","🐢"],
    ["lizard","🦎"],
    ["snake","🐍"],
    ["dragon_face","🐲"],
    ["dragon","🐉"],
    ["sauropod","🦕"],
    ["t-rex","🦖"],
    ["trex","🦖"],
    ["whale","🐳"],
    ["spouting_whale","🐳"],
    ["whale2","🐋"],
    ["whale","🐋"],
    ["dolphin","🐬"],
    ["flipper","🐬"],
    ["orca","🫍"],
    ["seal","🦭"],
    ["fish","🐟️"],
    ["tropical_fish","🐠"],
    ["blowfish","🐡"],
    ["shark","🦈"],
    ["octopus","🐙"],
    ["shell","🐚"],
    ["coral","🪸"],
    ["jellyfish","🪼"],
    ["crab","🦀"],
    ["lobster","🦞"],
    ["shrimp","🦐"],
    ["squid","🦑"],
    ["oyster","🦪"],
    ["snail","🐌"],
    ["butterfly","🦋"],
    ["bug","🐛"],
    ["ant","🐜"],
    ["bee","🐝"],
    ["honeybee","🐝"],
    ["beetle","🪲"],
    ["ladybug","🐞"],
    ["lady_beetle","🐞"],
    ["cricket","🦗"],
    ["cockroach","🪳"],
    ["spider","🕷️"],
    ["spider_web","🕸️"],
    ["scorpion","🦂"],
    ["mosquito","🦟"],
    ["fly","🪰"],
    ["worm","🪱"],
    ["microbe","🦠"],
    ["bouquet","💐"],
    ["cherry_blossom","🌸"],
    ["white_flower","💮"],
    ["lotus","🪷"],
    ["rosette","🏵️"],
    ["rose","🌹"],
    ["wilted_flower","🥀"],
    ["hibiscus","🌺"],
    ["sunflower","🌻"],
    ["blossom","🌼"],
    ["tulip","🌷"],
    ["hyacinth","🪻"],
    ["seedling","🌱"],
    ["potted_plant","🪴"],
    ["evergreen_tree","🌲"],
    ["deciduous_tree","🌳"],
    ["palm_tree","🌴"],
    ["cactus","🌵"],
    ["ear_of_rice","🌾"],
    ["sheaf_of_rice","🌾"],
    ["herb","🌿"],
    ["shamrock","☘️"],
    ["four_leaf_clover","🍀"],
    ["maple_leaf","🍁"],
    ["fallen_leaf","🍂"],
    ["leaves","🍃"],
    ["empty_nest","🪹"],
    ["nest","🪹"],
    ["nest_with_eggs","🪺"],
    ["mushroom","🍄"],
    ["leafless_tree","🪾"],
    ["grapes","🍇"],
    ["melon","🍈"],
    ["watermelon","🍉"],
    ["tangerine","🍊"],
    ["mandarin","🍊"],
    ["orange","🍊"],
    ["lemon","🍋"],
    ["lime","🍋‍🟩"],
    ["banana","🍌"],
    ["pineapple","🍍"],
    ["mango","🥭"],
    ["apple","🍎"],
    ["red_apple","🍎"],
    ["green_apple","🍏"],
    ["pear","🍐"],
    ["peach","🍑"],
    ["cherries","🍒"],
    ["strawberry","🍓"],
    ["blueberries","🫐"],
    ["kiwifruit","🥝"],
    ["kiwi_fruit","🥝"],
    ["kiwi","🥝"],
    ["tomato","🍅"],
    ["olive","🫒"],
    ["coconut","🥥"],
    ["avocado","🥑"],
    ["eggplant","🍆"],
    ["potato","🥔"],
    ["carrot","🥕"],
    ["corn","🌽"],
    ["ear_of_corn","🌽"],
    ["hot_pepper","🌶️"],
    ["bell_pepper","🫑"],
    ["cucumber","🥒"],
    ["leafy_green","🥬"],
    ["broccoli","🥦"],
    ["garlic","🧄"],
    ["onion","🧅"],
    ["peanuts","🥜"],
    ["beans","🫘"],
    ["chestnut","🌰"],
    ["ginger_root","🫚"],
    ["ginger","🫚"],
    ["pea_pod","🫛"],
    ["pea","🫛"],
    ["brown_mushroom","🍄‍🟫"],
    ["root_vegetable","🫜"],
    ["bread","🍞"],
    ["croissant","🥐"],
    ["baguette_bread","🥖"],
    ["flatbread","🫓"],
    ["pretzel","🥨"],
    ["bagel","🥯"],
    ["pancakes","🥞"],
    ["waffle","🧇"],
    ["cheese_wedge","🧀"],
    ["cheese","🧀"],
    ["meat_on_bone","🍖"],
    ["poultry_leg","🍗"],
    ["cut_of_meat","🥩"],
    ["bacon","🥓"],
    ["hamburger","🍔"],
    ["fries","🍟"],
    ["french_fries","🍟"],
    ["pizza","🍕"],
    ["hotdog","🌭"],
    ["sandwich","🥪"],
    ["taco","🌮"],
    ["burrito","🌯"],
    ["tamale","🫔"],
    ["stuffed_flatbread","🥙"],
    ["falafel","🧆"],
    ["egg","🥚"],
    ["fried_egg","🍳"],
    ["cooking","🍳"],
    ["shallow_pan_of_food","🥘"],
    ["stew","🍲"],
    ["pot_of_food","🍲"],
    ["fondue","🫕"],
    ["bowl_with_spoon","🥣"],
    ["green_salad","🥗"],
    ["salad","🥗"],
    ["popcorn","🍿"],
    ["butter","🧈"],
    ["salt","🧂"],
    ["canned_food","🥫"],
    ["bento","🍱"],
    ["bento_box","🍱"],
    ["rice_cracker","🍘"],
    ["rice_ball","🍙"],
    ["rice","🍚"],
    ["cooked_rice","🍚"],
    ["curry","🍛"],
    ["curry_rice","🍛"],
    ["ramen","🍜"],
    ["steaming_bowl","🍜"],
    ["spaghetti","🍝"],
    ["sweet_potato","🍠"],
    ["oden","🍢"],
    ["sushi","🍣"],
    ["fried_shrimp","🍤"],
    ["fish_cake","🍥"],
    ["moon_cake","🥮"],
    ["dango","🍡"],
    ["dumpling","🥟"],
    ["fortune_cookie","🥠"],
    ["takeout_box","🥡"],
    ["icecream","🍦"],
    ["soft_serve","🍦"],
    ["shaved_ice","🍧"],
    ["ice_cream","🍨"],
    ["doughnut","🍩"],
    ["cookie","🍪"],
    ["birthday","🎂"],
    ["birthday_cake","🎂"],
    ["cake","🍰"],
    ["shortcake","🍰"],
    ["cupcake","🧁"],
    ["pie","🥧"],
    ["chocolate_bar","🍫"],
    ["candy","🍬"],
    ["lollipop","🍭"],
    ["custard","🍮"],
    ["honey_pot","🍯"],
    ["baby_bottle","🍼"],
    ["glass_of_milk","🥛"],
    ["milk_glass","🥛"],
    ["milk","🥛"],
    ["coffee","☕️"],
    ["teapot","🫖"],
    ["tea","🍵"],
    ["sake","🍶"],
    ["champagne","🍾"],
    ["wine_glass","🍷"],
    ["cocktail","🍸️"],
    ["tropical_drink","🍹"],
    ["beer","🍺"],
    ["beers","🍻"],
    ["clinking_glasses","🥂"],
    ["tumbler_glass","🥃"],
    ["whisky","🥃"],
    ["pouring_liquid","🫗"],
    ["pour","🫗"],
    ["cup_with_straw","🥤"],
    ["bubble_tea","🧋"],
    ["boba_drink","🧋"],
    ["beverage_box","🧃"],
    ["juice_box","🧃"],
    ["mate_drink","🧉"],
    ["mate","🧉"],
    ["ice_cube","🧊"],
    ["ice","🧊"],
    ["chopsticks","🥢"],
    ["knife_fork_plate","🍽️"],
    ["plate_with_cutlery","🍽️"],
    ["fork_knife_plate","🍽️"],
    ["fork_and_knife","🍴"],
    ["spoon","🥄"],
    ["hocho","🔪"],
    ["knife","🔪"],
    ["jar","🫙"],
    ["amphora","🏺"],
    ["earth_africa","🌍️"],
    ["earth_europe","🌍️"],
    ["earth_americas","🌎️"],
    ["earth_asia","🌏️"],
    ["globe_with_meridians","🌐"],
    ["world_map","🗺️"],
    ["japan","🗾"],
    ["japan_map","🗾"],
    ["compass","🧭"],
    ["snow_capped_mountain","🏔️"],
    ["mountain_snow","🏔️"],
    ["mountain","⛰️"],
    ["landslide","🛘"],
    ["volcano","🌋"],
    ["mount_fuji","🗻"],
    ["camping","🏕️"],
    ["beach_with_umbrella","🏖️"],
    ["beach_umbrella","🏖️"],
    ["beach","🏖️"],
    ["desert","🏜️"],
    ["desert_island","🏝️"],
    ["island","🏝️"],
    ["national_park","🏞️"],
    ["stadium","🏟️"],
    ["classical_building","🏛️"],
    ["building_construction","🏗️"],
    ["construction_site","🏗️"],
    ["bricks","🧱"],
    ["rock","🪨"],
    ["wood","🪵"],
    ["hut","🛖"],
    ["house_buildings","🏘️"],
    ["houses","🏘️"],
    ["homes","🏘️"],
    ["derelict_house_building","🏚️"],
    ["derelict_house","🏚️"],
    ["house_abandoned","🏚️"],
    ["house","🏠️"],
    ["house_with_garden","🏡"],
    ["office","🏢"],
    ["post_office","🏣"],
    ["european_post_office","🏤"],
    ["hospital","🏥"],
    ["bank","🏦"],
    ["hotel","🏨"],
    ["love_hotel","🏩"],
    ["convenience_store","🏪"],
    ["school","🏫"],
    ["department_store","🏬"],
    ["factory","🏭️"],
    ["japanese_castle","🏯"],
    ["european_castle","🏰"],
    ["castle","🏰"],
    ["wedding","💒"],
    ["tokyo_tower","🗼"],
    ["statue_of_liberty","🗽"],
    ["church","⛪️"],
    ["mosque","🕌"],
    ["hindu_temple","🛕"],
    ["synagogue","🕍"],
    ["shinto_shrine","⛩️"],
    ["kaaba","🕋"],
    ["fountain","⛲️"],
    ["tent","⛺️"],
    ["foggy","🌁"],
    ["night_with_stars","🌃"],
    ["cityscape","🏙️"],
    ["sunrise_over_mountains","🌄"],
    ["sunrise","🌅"],
    ["city_sunset","🌆"],
    ["city_dusk","🌆"],
    ["city_sunrise","🌇"],
    ["city_sunset","🌇"],
    ["bridge_at_night","🌉"],
    ["hotsprings","♨️"],
    ["carousel_horse","🎠"],
    ["playground_slide","🛝"],
    ["slide","🛝"],
    ["ferris_wheel","🎡"],
    ["roller_coaster","🎢"],
    ["barber","💈"],
    ["barber_pole","💈"],
    ["circus_tent","🎪"],
    ["steam_locomotive","🚂"],
    ["railway_car","🚃"],
    ["bullettrain_side","🚄"],
    ["bullettrain_front","🚅"],
    ["train2","🚆"],
    ["train","🚆"],
    ["metro","🚇️"],
    ["light_rail","🚈"],
    ["station","🚉"],
    ["tram","🚊"],
    ["monorail","🚝"],
    ["mountain_railway","🚞"],
    ["train","🚋"],
    ["tram_car","🚋"],
    ["bus","🚌"],
    ["oncoming_bus","🚍️"],
    ["trolleybus","🚎"],
    ["minibus","🚐"],
    ["ambulance","🚑️"],
    ["fire_engine","🚒"],
    ["police_car","🚓"],
    ["oncoming_police_car","🚔️"],
    ["taxi","🚕"],
    ["oncoming_taxi","🚖"],
    ["car","🚗"],
    ["red_car","🚗"],
    ["oncoming_automobile","🚘️"],
    ["blue_car","🚙"],
    ["suv","🚙"],
    ["pickup_truck","🛻"],
    ["truck","🚚"],
    ["delivery_truck","🚚"],
    ["articulated_lorry","🚛"],
    ["tractor","🚜"],
    ["racing_car","🏎️"],
    ["racing_motorcycle","🏍️"],
    ["motorcycle","🏍️"],
    ["motor_scooter","🛵"],
    ["manual_wheelchair","🦽"],
    ["motorized_wheelchair","🦼"],
    ["auto_rickshaw","🛺"],
    ["bike","🚲️"],
    ["bicycle","🚲️"],
    ["scooter","🛴"],
    ["kick_scooter","🛴"],
    ["skateboard","🛹"],
    ["roller_skate","🛼"],
    ["busstop","🚏"],
    ["motorway","🛣️"],
    ["railway_track","🛤️"],
    ["oil_drum","🛢️"],
    ["fuelpump","⛽️"],
    ["wheel","🛞"],
    ["rotating_light","🚨"],
    ["traffic_light","🚥"],
    ["vertical_traffic_light","🚦"],
    ["octagonal_sign","🛑"],
    ["stop_sign","🛑"],
    ["construction","🚧"],
    ["anchor","⚓️"],
    ["ring_buoy","🛟"],
    ["lifebuoy","🛟"],
    ["boat","⛵️"],
    ["sailboat","⛵️"],
    ["canoe","🛶"],
    ["speedboat","🚤"],
    ["passenger_ship","🛳️"],
    ["cruise_ship","🛳️"],
    ["ferry","⛴️"],
    ["motor_boat","🛥️"],
    ["motorboat","🛥️"],
    ["ship","🚢"],
    ["airplane","✈️"],
    ["small_airplane","🛩️"],
    ["airplane_departure","🛫"],
    ["flight_departure","🛫"],
    ["airplane_arriving","🛬"],
    ["flight_arrival","🛬"],
    ["parachute","🪂"],
    ["seat","💺"],
    ["helicopter","🚁"],
    ["suspension_railway","🚟"],
    ["mountain_cableway","🚠"],
    ["aerial_tramway","🚡"],
    ["satellite","🛰️"],
    ["artificial_satellite","🛰️"],
    ["rocket","🚀"],
    ["flying_saucer","🛸"],
    ["bellhop_bell","🛎️"],
    ["bellhop","🛎️"],
    ["luggage","🧳"],
    ["hourglass","⌛️"],
    ["hourglass_flowing_sand","⏳️"],
    ["watch","⌚️"],
    ["alarm_clock","⏰️"],
    ["stopwatch","⏱️"],
    ["timer_clock","⏲️"],
    ["mantelpiece_clock","🕰️"],
    ["clock","🕰️"],
    ["clock12","🕛️"],
    ["clock1230","🕧️"],
    ["clock1","🕐️"],
    ["clock130","🕜️"],
    ["clock2","🕑️"],
    ["clock230","🕝️"],
    ["clock3","🕒️"],
    ["clock330","🕞️"],
    ["clock4","🕓️"],
    ["clock430","🕟️"],
    ["clock5","🕔️"],
    ["clock530","🕠️"],
    ["clock6","🕕️"],
    ["clock630","🕡️"],
    ["clock7","🕖️"],
    ["clock730","🕢️"],
    ["clock8","🕗️"],
    ["clock830","🕣️"],
    ["clock9","🕘️"],
    ["clock930","🕤️"],
    ["clock10","🕙️"],
    ["clock1030","🕥️"],
    ["clock11","🕚️"],
    ["clock1130","🕦️"],
    ["new_moon","🌑"],
    ["waxing_crescent_moon","🌒"],
    ["first_quarter_moon","🌓"],
    ["moon","🌔"],
    ["waxing_gibbous_moon","🌔"],
    ["full_moon","🌕️"],
    ["waning_gibbous_moon","🌖"],
    ["last_quarter_moon","🌗"],
    ["waning_crescent_moon","🌘"],
    ["crescent_moon","🌙"],
    ["new_moon_with_face","🌚"],
    ["first_quarter_moon_with_face","🌛"],
    ["last_quarter_moon_with_face","🌜️"],
    ["thermometer","🌡️"],
    ["sunny","☀️"],
    ["sun","☀️"],
    ["full_moon_with_face","🌝"],
    ["sun_with_face","🌞"],
    ["ringed_planet","🪐"],
    ["saturn","🪐"],
    ["star","⭐️"],
    ["star2","🌟"],
    ["glowing_star","🌟"],
    ["stars","🌠"],
    ["shooting_star","🌠"],
    ["milky_way","🌌"],
    ["cloud","☁️"],
    ["partly_sunny","⛅️"],
    ["sun_behind_cloud","⛅️"],
    ["thunder_cloud_and_rain","⛈️"],
    ["cloud_with_lightning_and_rain","⛈️"],
    ["stormy","⛈️"],
    ["mostly_sunny","🌤️"],
    ["sun_small_cloud","🌤️"],
    ["sun_behind_small_cloud","🌤️"],
    ["sunny","🌤️"],
    ["barely_sunny","🌥️"],
    ["sun_behind_cloud","🌥️"],
    ["sun_behind_large_cloud","🌥️"],
    ["cloudy","🌥️"],
    ["partly_sunny_rain","🌦️"],
    ["sun_behind_rain_cloud","🌦️"],
    ["sun_and_rain","🌦️"],
    ["rain_cloud","🌧️"],
    ["cloud_with_rain","🌧️"],
    ["rainy","🌧️"],
    ["snow_cloud","🌨️"],
    ["cloud_with_snow","🌨️"],
    ["snowy","🌨️"],
    ["lightning","🌩️"],
    ["lightning_cloud","🌩️"],
    ["cloud_with_lightning","🌩️"],
    ["tornado","🌪️"],
    ["tornado_cloud","🌪️"],
    ["fog","🌫️"],
    ["wind_blowing_face","🌬️"],
    ["wind_face","🌬️"],
    ["cyclone","🌀"],
    ["rainbow","🌈"],
    ["closed_umbrella","🌂"],
    ["umbrella","☂️"],
    ["open_umbrella","☂️"],
    ["umbrella_with_rain_drops","☔️"],
    ["umbrella","☔️"],
    ["umbrella_with_rain","☔️"],
    ["umbrella_on_ground","⛱️"],
    ["parasol_on_ground","⛱️"],
    ["beach_umbrella","⛱️"],
    ["zap","⚡️"],
    ["high_voltage","⚡️"],
    ["snowflake","❄️"],
    ["snowman","☃️"],
    ["snowman_with_snow","☃️"],
    ["snowman2","☃️"],
    ["snowman_without_snow","⛄️"],
    ["snowman","⛄️"],
    ["comet","☄️"],
    ["fire","🔥"],
    ["droplet","💧"],
    ["ocean","🌊"],
    ["water_wave","🌊"],
    ["jack_o_lantern","🎃"],
    ["christmas_tree","🎄"],
    ["fireworks","🎆"],
    ["sparkler","🎇"],
    ["firecracker","🧨"],
    ["sparkles","✨️"],
    ["balloon","🎈"],
    ["tada","🎉"],
    ["party","🎉"],
    ["party_popper","🎉"],
    ["confetti_ball","🎊"],
    ["tanabata_tree","🎋"],
    ["bamboo","🎍"],
    ["dolls","🎎"],
    ["flags","🎏"],
    ["carp_streamer","🎏"],
    ["wind_chime","🎐"],
    ["rice_scene","🎑"],
    ["moon_ceremony","🎑"],
    ["red_envelope","🧧"],
    ["ribbon","🎀"],
    ["gift","🎁"],
    ["reminder_ribbon","🎗️"],
    ["admission_tickets","🎟️"],
    ["tickets","🎟️"],
    ["ticket","🎫"],
    ["medal","🎖️"],
    ["medal_military","🎖️"],
    ["military_medal","🎖️"],
    ["trophy","🏆️"],
    ["sports_medal","🏅"],
    ["medal_sports","🏅"],
    ["first_place_medal","🥇"],
    ["1st_place_medal","🥇"],
    ["1st","🥇"],
    ["second_place_medal","🥈"],
    ["2nd_place_medal","🥈"],
    ["2nd","🥈"],
    ["third_place_medal","🥉"],
    ["3rd_place_medal","🥉"],
    ["3rd","🥉"],
    ["soccer","⚽️"],
    ["baseball","⚾️"],
    ["softball","🥎"],
    ["basketball","🏀"],
    ["volleyball","🏐"],
    ["football","🏈"],
    ["rugby_football","🏉"],
    ["tennis","🎾"],
    ["flying_disc","🥏"],
    ["bowling","🎳"],
    ["cricket_bat_and_ball","🏏"],
    ["cricket_game","🏏"],
    ["field_hockey_stick_and_ball","🏑"],
    ["field_hockey","🏑"],
    ["ice_hockey_stick_and_puck","🏒"],
    ["ice_hockey","🏒"],
    ["hockey","🏒"],
    ["lacrosse","🥍"],
    ["table_tennis_paddle_and_ball","🏓"],
    ["ping_pong","🏓"],
    ["badminton_racquet_and_shuttlecock","🏸"],
    ["badminton","🏸"],
    ["boxing_glove","🥊"],
    ["martial_arts_uniform","🥋"],
    ["goal_net","🥅"],
    ["golf","⛳️"],
    ["ice_skate","⛸️"],
    ["fishing_pole_and_fish","🎣"],
    ["fishing_pole","🎣"],
    ["diving_mask","🤿"],
    ["running_shirt_with_sash","🎽"],
    ["running_shirt","🎽"],
    ["ski","🎿"],
    ["sled","🛷"],
    ["curling_stone","🥌"],
    ["dart","🎯"],
    ["bullseye","🎯"],
    ["direct_hit","🎯"],
    ["yo-yo","🪀"],
    ["yo_yo","🪀"],
    ["kite","🪁"],
    ["gun","🔫"],
    ["pistol","🔫"],
    ["8ball","🎱"],
    ["billiards","🎱"],
    ["crystal_ball","🔮"],
    ["magic_wand","🪄"],
    ["video_game","🎮️"],
    ["controller","🎮️"],
    ["joystick","🕹️"],
    ["slot_machine","🎰"],
    ["game_die","🎲"],
    ["jigsaw","🧩"],
    ["puzzle_piece","🧩"],
    ["teddy_bear","🧸"],
    ["pinata","🪅"],
    ["mirror_ball","🪩"],
    ["disco","🪩"],
    ["disco_ball","🪩"],
    ["nesting_dolls","🪆"],
    ["spades","♠️"],
    ["hearts","♥️"],
    ["diamonds","♦️"],
    ["clubs","♣️"],
    ["chess_pawn","♟️"],
    ["black_joker","🃏"],
    ["mahjong","🀄️"],
    ["flower_playing_cards","🎴"],
    ["performing_arts","🎭️"],
    ["frame_with_picture","🖼️"],
    ["framed_picture","🖼️"],
    ["art","🎨"],
    ["palette","🎨"],
    ["thread","🧵"],
    ["sewing_needle","🪡"],
    ["yarn","🧶"],
    ["knot","🪢"],
    ["eyeglasses","👓️"],
    ["glasses","👓️"],
    ["dark_sunglasses","🕶️"],
    ["sunglasses","🕶️"],
    ["goggles","🥽"],
    ["lab_coat","🥼"],
    ["safety_vest","🦺"],
    ["necktie","👔"],
    ["shirt","👕"],
    ["tshirt","👕"],
    ["jeans","👖"],
    ["scarf","🧣"],
    ["gloves","🧤"],
    ["coat","🧥"],
    ["socks","🧦"],
    ["dress","👗"],
    ["kimono","👘"],
    ["sari","🥻"],
    ["one-piece_swimsuit","🩱"],
    ["one_piece_swimsuit","🩱"],
    ["briefs","🩲"],
    ["swim_brief","🩲"],
    ["shorts","🩳"],
    ["bikini","👙"],
    ["womans_clothes","👚"],
    ["folding_hand_fan","🪭"],
    ["folding_fan","🪭"],
    ["purse","👛"],
    ["handbag","👜"],
    ["pouch","👝"],
    ["clutch_bag","👝"],
    ["shopping_bags","🛍️"],
    ["shopping","🛍️"],
    ["school_satchel","🎒"],
    ["backpack","🎒"],
    ["thong_sandal","🩴"],
    ["mans_shoe","👞"],
    ["shoe","👞"],
    ["athletic_shoe","👟"],
    ["sneaker","👟"],
    ["hiking_boot","🥾"],
    ["womans_flat_shoe","🥿"],
    ["flat_shoe","🥿"],
    ["high_heel","👠"],
    ["sandal","👡"],
    ["ballet_shoes","🩰"],
    ["boot","👢"],
    ["hair_pick","🪮"],
    ["crown","👑"],
    ["womans_hat","👒"],
    ["tophat","🎩"],
    ["top_hat","🎩"],
    ["mortar_board","🎓️"],
    ["graduation_cap","🎓️"],
    ["billed_cap","🧢"],
    ["military_helmet","🪖"],
    ["helmet_with_white_cross","⛑️"],
    ["rescue_worker_helmet","⛑️"],
    ["helmet_with_cross","⛑️"],
    ["prayer_beads","📿"],
    ["lipstick","💄"],
    ["ring","💍"],
    ["gem","💎"],
    ["mute","🔇"],
    ["no_sound","🔇"],
    ["speaker","🔈️"],
    ["low_volume","🔈️"],
    ["quiet_sound","🔈️"],
    ["sound","🔉"],
    ["medium_volumne","🔉"],
    ["loud_sound","🔊"],
    ["high_volume","🔊"],
    ["loudspeaker","📢"],
    ["mega","📣"],
    ["megaphone","📣"],
    ["postal_horn","📯"],
    ["bell","🔔"],
    ["no_bell","🔕"],
    ["musical_score","🎼"],
    ["musical_note","🎵"],
    ["notes","🎶"],
    ["musical_notes","🎶"],
    ["studio_microphone","🎙️"],
    ["level_slider","🎚️"],
    ["control_knobs","🎛️"],
    ["microphone","🎤"],
    ["headphones","🎧️"],
    ["radio","📻️"],
    ["saxophone","🎷"],
    ["trumpet","🎺"],
    ["trombone","🪊"],
    ["accordion","🪗"],
    ["guitar","🎸"],
    ["musical_keyboard","🎹"],
    ["violin","🎻"],
    ["banjo","🪕"],
    ["drum_with_drumsticks","🥁"],
    ["drum","🥁"],
    ["long_drum","🪘"],
    ["maracas","🪇"],
    ["flute","🪈"],
    ["harp","🪉"],
    ["iphone","📱"],
    ["android","📱"],
    ["mobile_phone","📱"],
    ["calling","📲"],
    ["mobile_phone_arrow","📲"],
    ["phone","☎️"],
    ["telephone","☎️"],
    ["telephone_receiver","📞"],
    ["pager","📟️"],
    ["fax","📠"],
    ["fax_machine","📠"],
    ["battery","🔋"],
    ["low_battery","🪫"],
    ["electric_plug","🔌"],
    ["computer","💻️"],
    ["laptop","💻️"],
    ["desktop_computer","🖥️"],
    ["computer","🖥️"],
    ["printer","🖨️"],
    ["keyboard","⌨️"],
    ["three_button_mouse","🖱️"],
    ["computer_mouse","🖱️"],
    ["trackball","🖲️"],
    ["minidisc","💽"],
    ["computer_disk","💽"],
    ["floppy_disk","💾"],
    ["cd","💿️"],
    ["optical_disk","💿️"],
    ["dvd","📀"],
    ["abacus","🧮"],
    ["movie_camera","🎥"],
    ["film_frames","🎞️"],
    ["film_strip","🎞️"],
    ["film_projector","📽️"],
    ["clapper","🎬️"],
    ["tv","📺️"],
    ["camera","📷️"],
    ["camera_with_flash","📸"],
    ["camera_flash","📸"],
    ["video_camera","📹️"],
    ["vhs","📼"],
    ["videocassette","📼"],
    ["mag","🔍️"],
    ["mag_right","🔎"],
    ["candle","🕯️"],
    ["bulb","💡"],
    ["light_bulb","💡"],
    ["flashlight","🔦"],
    ["izakaya_lantern","🏮"],
    ["lantern","🏮"],
    ["red_paper_lantern","🏮"],
    ["diya_lamp","🪔"],
    ["notebook_with_decorative_cover","📔"],
    ["closed_book","📕"],
    ["book","📖"],
    ["open_book","📖"],
    ["green_book","📗"],
    ["blue_book","📘"],
    ["orange_book","📙"],
    ["books","📚️"],
    ["notebook","📓"],
    ["ledger","📒"],
    ["page_with_curl","📃"],
    ["scroll","📜"],
    ["page_facing_up","📄"],
    ["newspaper","📰"],
    ["rolled_up_newspaper","🗞️"],
    ["newspaper_roll","🗞️"],
    ["bookmark_tabs","📑"],
    ["bookmark","🔖"],
    ["label","🏷️"],
    ["coin","🪙"],
    ["moneybag","💰️"],
    ["treasure_chest","🪎"],
    ["yen","💴"],
    ["dollar","💵"],
    ["euro","💶"],
    ["pound","💷"],
    ["money_with_wings","💸"],
    ["credit_card","💳️"],
    ["receipt","🧾"],
    ["chart","💹"],
    ["email","✉️"],
    ["envelope","✉️"],
    ["e-mail","📧"],
    ["email","📧"],
    ["incoming_envelope","📨"],
    ["envelope_with_arrow","📩"],
    ["outbox_tray","📤️"],
    ["inbox_tray","📥️"],
    ["package","📦️"],
    ["mailbox","📫️"],
    ["mailbox_closed","📪️"],
    ["mailbox_with_mail","📬️"],
    ["mailbox_with_no_mail","📭️"],
    ["postbox","📮"],
    ["ballot_box_with_ballot","🗳️"],
    ["ballot_box","🗳️"],
    ["pencil2","✏️"],
    ["pencil","✏️"],
    ["black_nib","✒️"],
    ["lower_left_fountain_pen","🖋️"],
    ["fountain_pen","🖋️"],
    ["lower_left_ballpoint_pen","🖊️"],
    ["pen","🖊️"],
    ["lower_left_paintbrush","🖌️"],
    ["paintbrush","🖌️"],
    ["lower_left_crayon","🖍️"],
    ["crayon","🖍️"],
    ["memo","📝"],
    ["pencil","📝"],
    ["briefcase","💼"],
    ["file_folder","📁"],
    ["open_file_folder","📂"],
    ["card_index_dividers","🗂️"],
    ["date","📅"],
    ["calendar","📆"],
    ["spiral_note_pad","🗒️"],
    ["spiral_notepad","🗒️"],
    ["notepad_spiral","🗒️"],
    ["spiral_calendar_pad","🗓️"],
    ["spiral_calendar","🗓️"],
    ["calendar_spiral","🗓️"],
    ["card_index","📇"],
    ["chart_with_upwards_trend","📈"],
    ["chart_increasing","📈"],
    ["chart_with_downwards_trend","📉"],
    ["chart_decreasing","📉"],
    ["bar_chart","📊"],
    ["clipboard","📋️"],
    ["pushpin","📌"],
    ["round_pushpin","📍"],
    ["paperclip","📎"],
    ["linked_paperclips","🖇️"],
    ["paperclips","🖇️"],
    ["straight_ruler","📏"],
    ["triangular_ruler","📐"],
    ["scissors","✂️"],
    ["card_file_box","🗃️"],
    ["file_cabinet","🗄️"],
    ["wastebasket","🗑️"],
    ["trashcan","🗑️"],
    ["lock","🔒️"],
    ["locked","🔒️"],
    ["unlock","🔓️"],
    ["unlocked","🔓️"],
    ["lock_with_ink_pen","🔏"],
    ["locked_with_pen","🔏"],
    ["closed_lock_with_key","🔐"],
    ["locked_with_key","🔐"],
    ["key","🔑"],
    ["old_key","🗝️"],
    ["hammer","🔨"],
    ["axe","🪓"],
    ["pick","⛏️"],
    ["hammer_and_pick","⚒️"],
    ["hammer_and_wrench","🛠️"],
    ["dagger_knife","🗡️"],
    ["dagger","🗡️"],
    ["crossed_swords","⚔️"],
    ["bomb","💣️"],
    ["boomerang","🪃"],
    ["bow_and_arrow","🏹"],
    ["shield","🛡️"],
    ["carpentry_saw","🪚"],
    ["wrench","🔧"],
    ["screwdriver","🪛"],
    ["nut_and_bolt","🔩"],
    ["gear","⚙️"],
    ["compression","🗜️"],
    ["clamp","🗜️"],
    ["scales","⚖️"],
    ["balance_scale","⚖️"],
    ["probing_cane","🦯"],
    ["white_cane","🦯"],
    ["link","🔗"],
    ["broken_chain","⛓️‍💥"],
    ["chains","⛓️"],
    ["hook","🪝"],
    ["toolbox","🧰"],
    ["magnet","🧲"],
    ["ladder","🪜"],
    ["shovel","🪏"],
    ["alembic","⚗️"],
    ["test_tube","🧪"],
    ["petri_dish","🧫"],
    ["dna","🧬"],
    ["double_helix","🧬"],
    ["microscope","🔬"],
    ["telescope","🔭"],
    ["satellite_antenna","📡"],
    ["satellite","📡"],
    ["syringe","💉"],
    ["drop_of_blood","🩸"],
    ["pill","💊"],
    ["adhesive_bandage","🩹"],
    ["bandaid","🩹"],
    ["crutch","🩼"],
    ["stethoscope","🩺"],
    ["x-ray","🩻"],
    ["x_ray","🩻"],
    ["xray","🩻"],
    ["door","🚪"],
    ["elevator","🛗"],
    ["mirror","🪞"],
    ["window","🪟"],
    ["bed","🛏️"],
    ["couch_and_lamp","🛋️"],
    ["chair","🪑"],
    ["toilet","🚽"],
    ["plunger","🪠"],
    ["shower","🚿"],
    ["bathtub","🛁"],
    ["mouse_trap","🪤"],
    ["razor","🪒"],
    ["lotion_bottle","🧴"],
    ["safety_pin","🧷"],
    ["broom","🧹"],
    ["basket","🧺"],
    ["roll_of_paper","🧻"],
    ["toilet_paper","🧻"],
    ["bucket","🪣"],
    ["soap","🧼"],
    ["bubbles","🫧"],
    ["toothbrush","🪥"],
    ["sponge","🧽"],
    ["fire_extinguisher","🧯"],
    ["shopping_trolley","🛒"],
    ["shopping_cart","🛒"],
    ["smoking","🚬"],
    ["cigarette","🚬"],
    ["coffin","⚰️"],
    ["headstone","🪦"],
    ["funeral_urn","⚱️"],
    ["nazar_amulet","🧿"],
    ["hamsa","🪬"],
    ["moyai","🗿"],
    ["moai","🗿"],
    ["placard","🪧"],
    ["identification_card","🪪"],
    ["id_card","🪪"],
    ["atm","🏧"],
    ["put_litter_in_its_place","🚮"],
    ["litter_bin","🚮"],
    ["potable_water","🚰"],
    ["wheelchair","♿️"],
    ["handicapped","♿️"],
    ["mens","🚹️"],
    ["womens","🚺️"],
    ["restroom","🚻"],
    ["bathroom","🚻"],
    ["baby_symbol","🚼️"],
    ["wc","🚾"],
    ["water_closet","🚾"],
    ["passport_control","🛂"],
    ["customs","🛃"],
    ["baggage_claim","🛄"],
    ["left_luggage","🛅"],
    ["warning","⚠️"],
    ["children_crossing","🚸"],
    ["no_entry","⛔️"],
    ["no_entry_sign","🚫"],
    ["no_bicycles","🚳"],
    ["no_smoking","🚭️"],
    ["do_not_litter","🚯"],
    ["no_littering","🚯"],
    ["non-potable_water","🚱"],
    ["no_pedestrians","🚷"],
    ["no_mobile_phones","📵"],
    ["underage","🔞"],
    ["no_one_under_18","🔞"],
    ["radioactive_sign","☢️"],
    ["radioactive","☢️"],
    ["biohazard_sign","☣️"],
    ["biohazard","☣️"],
    ["arrow_up","⬆️"],
    ["arrow_upper_right","↗️"],
    ["arrow_right","➡️"],
    ["arrow_lower_right","↘️"],
    ["arrow_down","⬇️"],
    ["arrow_lower_left","↙️"],
    ["arrow_left","⬅️"],
    ["arrow_upper_left","↖️"],
    ["arrow_up_down","↕️"],
    ["left_right_arrow","↔️"],
    ["leftwards_arrow_with_hook","↩️"],
    ["arrow_left_hook","↩️"],
    ["arrow_right_hook","↪️"],
    ["rightwards_arrow_with_hook","↪️"],
    ["arrow_heading_up","⤴️"],
    ["arrow_heading_down","⤵️"],
    ["arrows_clockwise","🔃"],
    ["clockwise","🔃"],
    ["arrows_counterclockwise","🔄"],
    ["counterclockwise","🔄"],
    ["back","🔙"],
    ["end","🔚"],
    ["on","🔛"],
    ["soon","🔜"],
    ["top","🔝"],
    ["place_of_worship","🛐"],
    ["atom_symbol","⚛️"],
    ["atom","⚛️"],
    ["om_symbol","🕉️"],
    ["om","🕉️"],
    ["star_of_david","✡️"],
    ["wheel_of_dharma","☸️"],
    ["yin_yang","☯️"],
    ["latin_cross","✝️"],
    ["orthodox_cross","☦️"],
    ["star_and_crescent","☪️"],
    ["peace_symbol","☮️"],
    ["peace","☮️"],
    ["menorah_with_nine_branches","🕎"],
    ["menorah","🕎"],
    ["six_pointed_star","🔯"],
    ["khanda","🪯"],
    ["aries","♈️"],
    ["taurus","♉️"],
    ["gemini","♊️"],
    ["cancer","♋️"],
    ["leo","♌️"],
    ["virgo","♍️"],
    ["libra","♎️"],
    ["scorpius","♏️"],
    ["sagittarius","♐️"],
    ["capricorn","♑️"],
    ["aquarius","♒️"],
    ["pisces","♓️"],
    ["ophiuchus","⛎️"],
    ["twisted_rightwards_arrows","🔀"],
    ["shuffle","🔀"],
    ["repeat","🔁"],
    ["repeat_one","🔂"],
    ["arrow_forward","▶️"],
    ["play","▶️"],
    ["fast_forward","⏩️"],
    ["black_right_pointing_double_triangle_with_vertical_bar","⏭️"],
    ["next_track_button","⏭️"],
    ["next_track","⏭️"],
    ["black_right_pointing_triangle_with_double_vertical_bar","⏯️"],
    ["play_or_pause_button","⏯️"],
    ["play_pause","⏯️"],
    ["arrow_backward","◀️"],
    ["reverse","◀️"],
    ["rewind","⏪️"],
    ["fast_reverse","⏪️"],
    ["black_left_pointing_double_triangle_with_vertical_bar","⏮️"],
    ["previous_track_button","⏮️"],
    ["previous_track","⏮️"],
    ["arrow_up_small","🔼"],
    ["up","🔼"],
    ["arrow_double_up","⏫️"],
    ["fast_up","⏫️"],
    ["arrow_down_small","🔽"],
    ["down","🔽"],
    ["arrow_double_down","⏬️"],
    ["fast_down","⏬️"],
    ["double_vertical_bar","⏸️"],
    ["pause_button","⏸️"],
    ["pause","⏸️"],
    ["black_square_for_stop","⏹️"],
    ["stop_button","⏹️"],
    ["stop","⏹️"],
    ["black_circle_for_record","⏺️"],
    ["record_button","⏺️"],
    ["record","⏺️"],
    ["eject","⏏️"],
    ["eject_button","⏏️"],
    ["cinema","🎦"],
    ["low_brightness","🔅"],
    ["dim_button","🔅"],
    ["high_brightness","🔆"],
    ["bright_button","🔆"],
    ["signal_strength","📶"],
    ["antenna_bars","📶"],
    ["wireless","🛜"],
    ["vibration_mode","📳"],
    ["mobile_phone_off","📴"],
    ["female_sign","♀️"],
    ["female","♀️"],
    ["male_sign","♂️"],
    ["male","♂️"],
    ["transgender_symbol","⚧️"],
    ["heavy_multiplication_x","✖️"],
    ["multiplication","✖️"],
    ["multiply","✖️"],
    ["heavy_plus_sign","➕️"],
    ["plus","➕️"],
    ["heavy_minus_sign","➖️"],
    ["minus","➖️"],
    ["heavy_division_sign","➗️"],
    ["divide","➗️"],
    ["division","➗️"],
    ["heavy_equals_sign","🟰"],
    ["infinity","♾️"],
    ["bangbang","‼️"],
    ["double_exclamation","‼️"],
    ["interrobang","⁉️"],
    ["exclamation_question","⁉️"],
    ["question","❓️"],
    ["grey_question","❔️"],
    ["white_question","❔️"],
    ["grey_exclamation","❕️"],
    ["white_exclamation","❕️"],
    ["exclamation","❗️"],
    ["heavy_exclamation_mark","❗️"],
    ["wavy_dash","〰️"],
    ["currency_exchange","💱"],
    ["heavy_dollar_sign","💲"],
    ["medical_symbol","⚕️"],
    ["staff_of_aesculapius","⚕️"],
    ["medical","⚕️"],
    ["recycle","♻️"],
    ["recycling_symbol","♻️"],
    ["fleur_de_lis","⚜️"],
    ["fleur-de-lis","⚜️"],
    ["trident","🔱"],
    ["name_badge","📛"],
    ["beginner","🔰"],
    ["o","⭕️"],
    ["hollow_red_circle","⭕️"],
    ["red_o","⭕️"],
    ["white_check_mark","✅️"],
    ["check_mark_button","✅️"],
    ["ballot_box_with_check","☑️"],
    ["heavy_check_mark","✔️"],
    ["check_mark","✔️"],
    ["x","❌️"],
    ["cross_mark","❌️"],
    ["negative_squared_cross_mark","❎️"],
    ["cross_mark_button","❎️"],
    ["curly_loop","➰️"],
    ["loop","➿️"],
    ["double_curly_loop","➿️"],
    ["part_alternation_mark","〽️"],
    ["eight_spoked_asterisk","✳️"],
    ["eight_pointed_black_star","✴️"],
    ["sparkle","❇️"],
    ["copyright","©️"],
    ["registered","®️"],
    ["tm","™️"],
    ["trade_mark","™️"],
    ["splatter","🫟"],
    ["hash","#️⃣"],
    ["number_sign","#️⃣"],
    ["keycap_star","*️⃣"],
    ["asterisk","*️⃣"],
    ["zero","0️⃣"],
    ["one","1️⃣"],
    ["two","2️⃣"],
    ["three","3️⃣"],
    ["four","4️⃣"],
    ["five","5️⃣"],
    ["six","6️⃣"],
    ["seven","7️⃣"],
    ["eight","8️⃣"],
    ["nine","9️⃣"],
    ["keycap_ten","🔟"],
    ["ten","🔟"],
    ["capital_abcd","🔠"],
    ["abcd","🔡"],
    ["1234","🔢"],
    ["symbols","🔣"],
    ["abc","🔤"],
    ["a","🅰️"],
    ["a_blood","🅰️"],
    ["ab","🆎"],
    ["ab_blood","🆎"],
    ["b","🅱️"],
    ["b_blood","🅱️"],
    ["cl","🆑"],
    ["cool","🆒"],
    ["free","🆓"],
    ["information_source","ℹ️"],
    ["info","ℹ️"],
    ["id","🆔"],
    ["m","Ⓜ️"],
    ["new","🆕"],
    ["ng","🆖"],
    ["o2","🅾️"],
    ["o","🅾️"],
    ["o_blood","🅾️"],
    ["ok","🆗"],
    ["parking","🅿️"],
    ["sos","🆘"],
    ["up","🆙"],
    ["up2","🆙"],
    ["vs","🆚"],
    ["koko","🈁"],
    ["ja_here","🈁"],
    ["sa","🈂️"],
    ["ja_service_charge","🈂️"],
    ["u6708","🈷️"],
    ["ja_monthly_amount","🈷️"],
    ["u6709","🈶"],
    ["ja_not_free_of_carge","🈶"],
    ["u6307","🈯️"],
    ["ja_reserved","🈯️"],
    ["ideograph_advantage","🉐"],
    ["ja_bargain","🉐"],
    ["u5272","🈹"],
    ["ja_discount","🈹"],
    ["u7121","🈚️"],
    ["ja_free_of_charge","🈚️"],
    ["u7981","🈲"],
    ["ja_prohibited","🈲"],
    ["accept","🉑"],
    ["ja_acceptable","🉑"],
    ["u7533","🈸"],
    ["ja_application","🈸"],
    ["u5408","🈴"],
    ["ja_passing_grade","🈴"],
    ["u7a7a","🈳"],
    ["ja_vacancy","🈳"],
    ["congratulations","㊗️"],
    ["ja_congratulations","㊗️"],
    ["secret","㊙️"],
    ["ja_secret","㊙️"],
    ["u55b6","🈺"],
    ["ja_open_for_business","🈺"],
    ["u6e80","🈵"],
    ["ja_no_vacancy","🈵"],
    ["red_circle","🔴"],
    ["large_orange_circle","🟠"],
    ["orange_circle","🟠"],
    ["large_yellow_circle","🟡"],
    ["yellow_circle","🟡"],
    ["large_green_circle","🟢"],
    ["green_circle","🟢"],
    ["large_blue_circle","🔵"],
    ["blue_circle","🔵"],
    ["large_purple_circle","🟣"],
    ["purple_circle","🟣"],
    ["large_brown_circle","🟤"],
    ["brown_circle","🟤"],
    ["black_circle","⚫️"],
    ["white_circle","⚪️"],
    ["large_red_square","🟥"],
    ["red_square","🟥"],
    ["large_orange_square","🟧"],
    ["orange_square","🟧"],
    ["large_yellow_square","🟨"],
    ["yellow_square","🟨"],
    ["large_green_square","🟩"],
    ["green_square","🟩"],
    ["large_blue_square","🟦"],
    ["blue_square","🟦"],
    ["large_purple_square","🟪"],
    ["purple_square","🟪"],
    ["large_brown_square","🟫"],
    ["brown_square","🟫"],
    ["black_large_square","⬛️"],
    ["white_large_square","⬜️"],
    ["black_medium_square","◼️"],
    ["white_medium_square","◻️"],
    ["black_medium_small_square","◾️"],
    ["white_medium_small_square","◽️"],
    ["black_small_square","▪️"],
    ["white_small_square","▫️"],
    ["large_orange_diamond","🔶"],
    ["large_blue_diamond","🔷"],
    ["small_orange_diamond","🔸"],
    ["small_blue_diamond","🔹"],
    ["small_red_triangle","🔺"],
    ["small_red_triangle_down","🔻"],
    ["diamond_shape_with_a_dot_inside","💠"],
    ["diamond_with_a_dot","💠"],
    ["radio_button","🔘"],
    ["white_square_button","🔳"],
    ["black_square_button","🔲"],
    ["checkered_flag","🏁"],
    ["triangular_flag_on_post","🚩"],
    ["triangular_flag","🚩"],
    ["crossed_flags","🎌"],
    ["waving_black_flag","🏴"],
    ["black_flag","🏴"],
    ["waving_white_flag","🏳️"],
    ["white_flag","🏳️"],
    ["rainbow-flag","🏳️‍🌈"],
    ["rainbow_flag","🏳️‍🌈"],
    ["transgender_flag","🏳️‍⚧️"],
    ["pirate_flag","🏴‍☠️"],
    ["jolly_roger","🏴‍☠️"],
    ["flag-ac","🇦🇨"],
    ["ascension_island","🇦🇨"],
    ["flag_ac","🇦🇨"],
    ["flag-ad","🇦🇩"],
    ["andorra","🇦🇩"],
    ["flag_ad","🇦🇩"],
    ["flag-ae","🇦🇪"],
    ["united_arab_emirates","🇦🇪"],
    ["flag_ae","🇦🇪"],
    ["flag-af","🇦🇫"],
    ["afghanistan","🇦🇫"],
    ["flag_af","🇦🇫"],
    ["flag-ag","🇦🇬"],
    ["antigua_barbuda","🇦🇬"],
    ["flag_ag","🇦🇬"],
    ["flag-ai","🇦🇮"],
    ["anguilla","🇦🇮"],
    ["flag_ai","🇦🇮"],
    ["flag-al","🇦🇱"],
    ["albania","🇦🇱"],
    ["flag_al","🇦🇱"],
    ["flag-am","🇦🇲"],
    ["armenia","🇦🇲"],
    ["flag_am","🇦🇲"],
    ["flag-ao","🇦🇴"],
    ["angola","🇦🇴"],
    ["flag_ao","🇦🇴"],
    ["flag-aq","🇦🇶"],
    ["antarctica","🇦🇶"],
    ["flag_aq","🇦🇶"],
    ["flag-ar","🇦🇷"],
    ["argentina","🇦🇷"],
    ["flag_ar","🇦🇷"],
    ["flag-as","🇦🇸"],
    ["american_samoa","🇦🇸"],
    ["flag_as","🇦🇸"],
    ["flag-at","🇦🇹"],
    ["austria","🇦🇹"],
    ["flag_at","🇦🇹"],
    ["flag-au","🇦🇺"],
    ["australia","🇦🇺"],
    ["flag_au","🇦🇺"],
    ["flag-aw","🇦🇼"],
    ["aruba","🇦🇼"],
    ["flag_aw","🇦🇼"],
    ["flag-ax","🇦🇽"],
    ["aland_islands","🇦🇽"],
    ["flag_ax","🇦🇽"],
    ["flag-az","🇦🇿"],
    ["azerbaijan","🇦🇿"],
    ["flag_az","🇦🇿"],
    ["flag-ba","🇧🇦"],
    ["bosnia_herzegovina","🇧🇦"],
    ["flag_ba","🇧🇦"],
    ["flag-bb","🇧🇧"],
    ["barbados","🇧🇧"],
    ["flag_bb","🇧🇧"],
    ["flag-bd","🇧🇩"],
    ["bangladesh","🇧🇩"],
    ["flag_bd","🇧🇩"],
    ["flag-be","🇧🇪"],
    ["belgium","🇧🇪"],
    ["flag_be","🇧🇪"],
    ["flag-bf","🇧🇫"],
    ["burkina_faso","🇧🇫"],
    ["flag_bf","🇧🇫"],
    ["flag-bg","🇧🇬"],
    ["bulgaria","🇧🇬"],
    ["flag_bg","🇧🇬"],
    ["flag-bh","🇧🇭"],
    ["bahrain","🇧🇭"],
    ["flag_bh","🇧🇭"],
    ["flag-bi","🇧🇮"],
    ["burundi","🇧🇮"],
    ["flag_bi","🇧🇮"],
    ["flag-bj","🇧🇯"],
    ["benin","🇧🇯"],
    ["flag_bj","🇧🇯"],
    ["flag-bl","🇧🇱"],
    ["st_barthelemy","🇧🇱"],
    ["flag_bl","🇧🇱"],
    ["flag-bm","🇧🇲"],
    ["bermuda","🇧🇲"],
    ["flag_bm","🇧🇲"],
    ["flag-bn","🇧🇳"],
    ["brunei","🇧🇳"],
    ["flag_bn","🇧🇳"],
    ["flag-bo","🇧🇴"],
    ["bolivia","🇧🇴"],
    ["flag_bo","🇧🇴"],
    ["flag-bq","🇧🇶"],
    ["caribbean_netherlands","🇧🇶"],
    ["flag_bq","🇧🇶"],
    ["flag-br","🇧🇷"],
    ["brazil","🇧🇷"],
    ["flag_br","🇧🇷"],
    ["flag-bs","🇧🇸"],
    ["bahamas","🇧🇸"],
    ["flag_bs","🇧🇸"],
    ["flag-bt","🇧🇹"],
    ["bhutan","🇧🇹"],
    ["flag_bt","🇧🇹"],
    ["flag-bv","🇧🇻"],
    ["bouvet_island","🇧🇻"],
    ["flag_bv","🇧🇻"],
    ["flag-bw","🇧🇼"],
    ["botswana","🇧🇼"],
    ["flag_bw","🇧🇼"],
    ["flag-by","🇧🇾"],
    ["belarus","🇧🇾"],
    ["flag_by","🇧🇾"],
    ["flag-bz","🇧🇿"],
    ["belize","🇧🇿"],
    ["flag_bz","🇧🇿"],
    ["flag-ca","🇨🇦"],
    ["canada","🇨🇦"],
    ["flag_ca","🇨🇦"],
    ["flag-cc","🇨🇨"],
    ["cocos_islands","🇨🇨"],
    ["flag_cc","🇨🇨"],
    ["flag-cd","🇨🇩"],
    ["congo_kinshasa","🇨🇩"],
    ["flag_cd","🇨🇩"],
    ["flag-cf","🇨🇫"],
    ["central_african_republic","🇨🇫"],
    ["flag_cf","🇨🇫"],
    ["flag-cg","🇨🇬"],
    ["congo_brazzaville","🇨🇬"],
    ["flag_cg","🇨🇬"],
    ["flag-ch","🇨🇭"],
    ["switzerland","🇨🇭"],
    ["flag_ch","🇨🇭"],
    ["flag-ci","🇨🇮"],
    ["cote_divoire","🇨🇮"],
    ["flag_ci","🇨🇮"],
    ["flag-ck","🇨🇰"],
    ["cook_islands","🇨🇰"],
    ["flag_ck","🇨🇰"],
    ["flag-cl","🇨🇱"],
    ["chile","🇨🇱"],
    ["flag_cl","🇨🇱"],
    ["flag-cm","🇨🇲"],
    ["cameroon","🇨🇲"],
    ["flag_cm","🇨🇲"],
    ["cn","🇨🇳"],
    ["flag-cn","🇨🇳"],
    ["china","🇨🇳"],
    ["flag_cn","🇨🇳"],
    ["flag-co","🇨🇴"],
    ["colombia","🇨🇴"],
    ["flag_co","🇨🇴"],
    ["flag-cp","🇨🇵"],
    ["clipperton_island","🇨🇵"],
    ["flag_cp","🇨🇵"],
    ["flag-sark","🇨🇶"],
    ["flag_cq","🇨🇶"],
    ["sark","🇨🇶"],
    ["flag-cr","🇨🇷"],
    ["costa_rica","🇨🇷"],
    ["flag_cr","🇨🇷"],
    ["flag-cu","🇨🇺"],
    ["cuba","🇨🇺"],
    ["flag_cu","🇨🇺"],
    ["flag-cv","🇨🇻"],
    ["cape_verde","🇨🇻"],
    ["flag_cv","🇨🇻"],
    ["flag-cw","🇨🇼"],
    ["curacao","🇨🇼"],
    ["flag_cw","🇨🇼"],
    ["flag-cx","🇨🇽"],
    ["christmas_island","🇨🇽"],
    ["flag_cx","🇨🇽"],
    ["flag-cy","🇨🇾"],
    ["cyprus","🇨🇾"],
    ["flag_cy","🇨🇾"],
    ["flag-cz","🇨🇿"],
    ["czech_republic","🇨🇿"],
    ["czechia","🇨🇿"],
    ["flag_cz","🇨🇿"],
    ["de","🇩🇪"],
    ["flag-de","🇩🇪"],
    ["flag_de","🇩🇪"],
    ["germany","🇩🇪"],
    ["flag-dg","🇩🇬"],
    ["diego_garcia","🇩🇬"],
    ["flag_dg","🇩🇬"],
    ["flag-dj","🇩🇯"],
    ["djibouti","🇩🇯"],
    ["flag_dj","🇩🇯"],
    ["flag-dk","🇩🇰"],
    ["denmark","🇩🇰"],
    ["flag_dk","🇩🇰"],
    ["flag-dm","🇩🇲"],
    ["dominica","🇩🇲"],
    ["flag_dm","🇩🇲"],
    ["flag-do","🇩🇴"],
    ["dominican_republic","🇩🇴"],
    ["flag_do","🇩🇴"],
    ["flag-dz","🇩🇿"],
    ["algeria","🇩🇿"],
    ["flag_dz","🇩🇿"],
    ["flag-ea","🇪🇦"],
    ["ceuta_melilla","🇪🇦"],
    ["flag_ea","🇪🇦"],
    ["flag-ec","🇪🇨"],
    ["ecuador","🇪🇨"],
    ["flag_ec","🇪🇨"],
    ["flag-ee","🇪🇪"],
    ["estonia","🇪🇪"],
    ["flag_ee","🇪🇪"],
    ["flag-eg","🇪🇬"],
    ["egypt","🇪🇬"],
    ["flag_eg","🇪🇬"],
    ["flag-eh","🇪🇭"],
    ["western_sahara","🇪🇭"],
    ["flag_eh","🇪🇭"],
    ["flag-er","🇪🇷"],
    ["eritrea","🇪🇷"],
    ["flag_er","🇪🇷"],
    ["es","🇪🇸"],
    ["flag-es","🇪🇸"],
    ["flag_es","🇪🇸"],
    ["spain","🇪🇸"],
    ["flag-et","🇪🇹"],
    ["ethiopia","🇪🇹"],
    ["flag_et","🇪🇹"],
    ["flag-eu","🇪🇺"],
    ["eu","🇪🇺"],
    ["european_union","🇪🇺"],
    ["flag_eu","🇪🇺"],
    ["flag-fi","🇫🇮"],
    ["finland","🇫🇮"],
    ["flag_fi","🇫🇮"],
    ["flag-fj","🇫🇯"],
    ["fiji","🇫🇯"],
    ["flag_fj","🇫🇯"],
    ["flag-fk","🇫🇰"],
    ["falkland_islands","🇫🇰"],
    ["flag_fk","🇫🇰"],
    ["flag-fm","🇫🇲"],
    ["micronesia","🇫🇲"],
    ["flag_fm","🇫🇲"],
    ["flag-fo","🇫🇴"],
    ["faroe_islands","🇫🇴"],
    ["flag_fo","🇫🇴"],
    ["fr","🇫🇷"],
    ["flag-fr","🇫🇷"],
    ["flag_fr","🇫🇷"],
    ["france","🇫🇷"],
    ["flag-ga","🇬🇦"],
    ["gabon","🇬🇦"],
    ["flag_ga","🇬🇦"],
    ["gb","🇬🇧"],
    ["uk","🇬🇧"],
    ["flag-gb","🇬🇧"],
    ["flag_gb","🇬🇧"],
    ["united_kingdom","🇬🇧"],
    ["flag-gd","🇬🇩"],
    ["grenada","🇬🇩"],
    ["flag_gd","🇬🇩"],
    ["flag-ge","🇬🇪"],
    ["georgia","🇬🇪"],
    ["flag_ge","🇬🇪"],
    ["flag-gf","🇬🇫"],
    ["french_guiana","🇬🇫"],
    ["flag_gf","🇬🇫"],
    ["flag-gg","🇬🇬"],
    ["guernsey","🇬🇬"],
    ["flag_gg","🇬🇬"],
    ["flag-gh","🇬🇭"],
    ["ghana","🇬🇭"],
    ["flag_gh","🇬🇭"],
    ["flag-gi","🇬🇮"],
    ["gibraltar","🇬🇮"],
    ["flag_gi","🇬🇮"],
    ["flag-gl","🇬🇱"],
    ["greenland","🇬🇱"],
    ["flag_gl","🇬🇱"],
    ["flag-gm","🇬🇲"],
    ["gambia","🇬🇲"],
    ["flag_gm","🇬🇲"],
    ["flag-gn","🇬🇳"],
    ["guinea","🇬🇳"],
    ["flag_gn","🇬🇳"],
    ["flag-gp","🇬🇵"],
    ["guadeloupe","🇬🇵"],
    ["flag_gp","🇬🇵"],
    ["flag-gq","🇬🇶"],
    ["equatorial_guinea","🇬🇶"],
    ["flag_gq","🇬🇶"],
    ["flag-gr","🇬🇷"],
    ["greece","🇬🇷"],
    ["flag_gr","🇬🇷"],
    ["flag-gs","🇬🇸"],
    ["south_georgia_south_sandwich_islands","🇬🇸"],
    ["flag_gs","🇬🇸"],
    ["flag-gt","🇬🇹"],
    ["guatemala","🇬🇹"],
    ["flag_gt","🇬🇹"],
    ["flag-gu","🇬🇺"],
    ["guam","🇬🇺"],
    ["flag_gu","🇬🇺"],
    ["flag-gw","🇬🇼"],
    ["guinea_bissau","🇬🇼"],
    ["flag_gw","🇬🇼"],
    ["flag-gy","🇬🇾"],
    ["guyana","🇬🇾"],
    ["flag_gy","🇬🇾"],
    ["flag-hk","🇭🇰"],
    ["hong_kong","🇭🇰"],
    ["flag_hk","🇭🇰"],
    ["flag-hm","🇭🇲"],
    ["heard_mcdonald_islands","🇭🇲"],
    ["flag_hm","🇭🇲"],
    ["flag-hn","🇭🇳"],
    ["honduras","🇭🇳"],
    ["flag_hn","🇭🇳"],
    ["flag-hr","🇭🇷"],
    ["croatia","🇭🇷"],
    ["flag_hr","🇭🇷"],
    ["flag-ht","🇭🇹"],
    ["haiti","🇭🇹"],
    ["flag_ht","🇭🇹"],
    ["flag-hu","🇭🇺"],
    ["hungary","🇭🇺"],
    ["flag_hu","🇭🇺"],
    ["flag-ic","🇮🇨"],
    ["canary_islands","🇮🇨"],
    ["flag_ic","🇮🇨"],
    ["flag-id","🇮🇩"],
    ["indonesia","🇮🇩"],
    ["flag_id","🇮🇩"],
    ["flag-ie","🇮🇪"],
    ["ireland","🇮🇪"],
    ["flag_ie","🇮🇪"],
    ["flag-il","🇮🇱"],
    ["israel","🇮🇱"],
    ["flag_il","🇮🇱"],
    ["flag-im","🇮🇲"],
    ["isle_of_man","🇮🇲"],
    ["flag_im","🇮🇲"],
    ["flag-in","🇮🇳"],
    ["india","🇮🇳"],
    ["flag_in","🇮🇳"],
    ["flag-io","🇮🇴"],
    ["british_indian_ocean_territory","🇮🇴"],
    ["flag_io","🇮🇴"],
    ["flag-iq","🇮🇶"],
    ["iraq","🇮🇶"],
    ["flag_iq","🇮🇶"],
    ["flag-ir","🇮🇷"],
    ["iran","🇮🇷"],
    ["flag_ir","🇮🇷"],
    ["flag-is","🇮🇸"],
    ["iceland","🇮🇸"],
    ["flag_is","🇮🇸"],
    ["it","🇮🇹"],
    ["flag-it","🇮🇹"],
    ["flag_it","🇮🇹"],
    ["italy","🇮🇹"],
    ["flag-je","🇯🇪"],
    ["jersey","🇯🇪"],
    ["flag_je","🇯🇪"],
    ["flag-jm","🇯🇲"],
    ["jamaica","🇯🇲"],
    ["flag_jm","🇯🇲"],
    ["flag-jo","🇯🇴"],
    ["jordan","🇯🇴"],
    ["flag_jo","🇯🇴"],
    ["jp","🇯🇵"],
    ["flag-jp","🇯🇵"],
    ["flag_jp","🇯🇵"],
    ["japan","🇯🇵"],
    ["flag-ke","🇰🇪"],
    ["kenya","🇰🇪"],
    ["flag_ke","🇰🇪"],
    ["flag-kg","🇰🇬"],
    ["kyrgyzstan","🇰🇬"],
    ["flag_kg","🇰🇬"],
    ["flag-kh","🇰🇭"],
    ["cambodia","🇰🇭"],
    ["flag_kh","🇰🇭"],
    ["flag-ki","🇰🇮"],
    ["kiribati","🇰🇮"],
    ["flag_ki","🇰🇮"],
    ["flag-km","🇰🇲"],
    ["comoros","🇰🇲"],
    ["flag_km","🇰🇲"],
    ["flag-kn","🇰🇳"],
    ["st_kitts_nevis","🇰🇳"],
    ["flag_kn","🇰🇳"],
    ["flag-kp","🇰🇵"],
    ["north_korea","🇰🇵"],
    ["flag_kp","🇰🇵"],
    ["kr","🇰🇷"],
    ["flag-kr","🇰🇷"],
    ["flag_kr","🇰🇷"],
    ["south_korea","🇰🇷"],
    ["flag-kw","🇰🇼"],
    ["kuwait","🇰🇼"],
    ["flag_kw","🇰🇼"],
    ["flag-ky","🇰🇾"],
    ["cayman_islands","🇰🇾"],
    ["flag_ky","🇰🇾"],
    ["flag-kz","🇰🇿"],
    ["kazakhstan","🇰🇿"],
    ["flag_kz","🇰🇿"],
    ["flag-la","🇱🇦"],
    ["laos","🇱🇦"],
    ["flag_la","🇱🇦"],
    ["flag-lb","🇱🇧"],
    ["lebanon","🇱🇧"],
    ["flag_lb","🇱🇧"],
    ["flag-lc","🇱🇨"],
    ["st_lucia","🇱🇨"],
    ["flag_lc","🇱🇨"],
    ["flag-li","🇱🇮"],
    ["liechtenstein","🇱🇮"],
    ["flag_li","🇱🇮"],
    ["flag-lk","🇱🇰"],
    ["sri_lanka","🇱🇰"],
    ["flag_lk","🇱🇰"],
    ["flag-lr","🇱🇷"],
    ["liberia","🇱🇷"],
    ["flag_lr","🇱🇷"],
    ["flag-ls","🇱🇸"],
    ["lesotho","🇱🇸"],
    ["flag_ls","🇱🇸"],
    ["flag-lt","🇱🇹"],
    ["lithuania","🇱🇹"],
    ["flag_lt","🇱🇹"],
    ["flag-lu","🇱🇺"],
    ["luxembourg","🇱🇺"],
    ["flag_lu","🇱🇺"],
    ["flag-lv","🇱🇻"],
    ["latvia","🇱🇻"],
    ["flag_lv","🇱🇻"],
    ["flag-ly","🇱🇾"],
    ["libya","🇱🇾"],
    ["flag_ly","🇱🇾"],
    ["flag-ma","🇲🇦"],
    ["morocco","🇲🇦"],
    ["flag_ma","🇲🇦"],
    ["flag-mc","🇲🇨"],
    ["monaco","🇲🇨"],
    ["flag_mc","🇲🇨"],
    ["flag-md","🇲🇩"],
    ["moldova","🇲🇩"],
    ["flag_md","🇲🇩"],
    ["flag-me","🇲🇪"],
    ["montenegro","🇲🇪"],
    ["flag_me","🇲🇪"],
    ["flag-mf","🇲🇫"],
    ["st_martin","🇲🇫"],
    ["flag_mf","🇲🇫"],
    ["flag-mg","🇲🇬"],
    ["madagascar","🇲🇬"],
    ["flag_mg","🇲🇬"],
    ["flag-mh","🇲🇭"],
    ["marshall_islands","🇲🇭"],
    ["flag_mh","🇲🇭"],
    ["flag-mk","🇲🇰"],
    ["macedonia","🇲🇰"],
    ["flag_mk","🇲🇰"],
    ["flag-ml","🇲🇱"],
    ["mali","🇲🇱"],
    ["flag_ml","🇲🇱"],
    ["flag-mm","🇲🇲"],
    ["myanmar","🇲🇲"],
    ["burma","🇲🇲"],
    ["flag_mm","🇲🇲"],
    ["flag-mn","🇲🇳"],
    ["mongolia","🇲🇳"],
    ["flag_mn","🇲🇳"],
    ["flag-mo","🇲🇴"],
    ["macau","🇲🇴"],
    ["flag_mo","🇲🇴"],
    ["macao","🇲🇴"],
    ["flag-mp","🇲🇵"],
    ["northern_mariana_islands","🇲🇵"],
    ["flag_mp","🇲🇵"],
    ["flag-mq","🇲🇶"],
    ["martinique","🇲🇶"],
    ["flag_mq","🇲🇶"],
    ["flag-mr","🇲🇷"],
    ["mauritania","🇲🇷"],
    ["flag_mr","🇲🇷"],
    ["flag-ms","🇲🇸"],
    ["montserrat","🇲🇸"],
    ["flag_ms","🇲🇸"],
    ["flag-mt","🇲🇹"],
    ["malta","🇲🇹"],
    ["flag_mt","🇲🇹"],
    ["flag-mu","🇲🇺"],
    ["mauritius","🇲🇺"],
    ["flag_mu","🇲🇺"],
    ["flag-mv","🇲🇻"],
    ["maldives","🇲🇻"],
    ["flag_mv","🇲🇻"],
    ["flag-mw","🇲🇼"],
    ["malawi","🇲🇼"],
    ["flag_mw","🇲🇼"],
    ["flag-mx","🇲🇽"],
    ["mexico","🇲🇽"],
    ["flag_mx","🇲🇽"],
    ["flag-my","🇲🇾"],
    ["malaysia","🇲🇾"],
    ["flag_my","🇲🇾"],
    ["flag-mz","🇲🇿"],
    ["mozambique","🇲🇿"],
    ["flag_mz","🇲🇿"],
    ["flag-na","🇳🇦"],
    ["namibia","🇳🇦"],
    ["flag_na","🇳🇦"],
    ["flag-nc","🇳🇨"],
    ["new_caledonia","🇳🇨"],
    ["flag_nc","🇳🇨"],
    ["flag-ne","🇳🇪"],
    ["niger","🇳🇪"],
    ["flag_ne","🇳🇪"],
    ["flag-nf","🇳🇫"],
    ["norfolk_island","🇳🇫"],
    ["flag_nf","🇳🇫"],
    ["flag-ng","🇳🇬"],
    ["nigeria","🇳🇬"],
    ["flag_ng","🇳🇬"],
    ["flag-ni","🇳🇮"],
    ["nicaragua","🇳🇮"],
    ["flag_ni","🇳🇮"],
    ["flag-nl","🇳🇱"],
    ["netherlands","🇳🇱"],
    ["flag_nl","🇳🇱"],
    ["flag-no","🇳🇴"],
    ["norway","🇳🇴"],
    ["flag_no","🇳🇴"],
    ["flag-np","🇳🇵"],
    ["nepal","🇳🇵"],
    ["flag_np","🇳🇵"],
    ["flag-nr","🇳🇷"],
    ["nauru","🇳🇷"],
    ["flag_nr","🇳🇷"],
    ["flag-nu","🇳🇺"],
    ["niue","🇳🇺"],
    ["flag_nu","🇳🇺"],
    ["flag-nz","🇳🇿"],
    ["new_zealand","🇳🇿"],
    ["flag_nz","🇳🇿"],
    ["flag-om","🇴🇲"],
    ["oman","🇴🇲"],
    ["flag_om","🇴🇲"],
    ["flag-pa","🇵🇦"],
    ["panama","🇵🇦"],
    ["flag_pa","🇵🇦"],
    ["flag-pe","🇵🇪"],
    ["peru","🇵🇪"],
    ["flag_pe","🇵🇪"],
    ["flag-pf","🇵🇫"],
    ["french_polynesia","🇵🇫"],
    ["flag_pf","🇵🇫"],
    ["flag-pg","🇵🇬"],
    ["papua_new_guinea","🇵🇬"],
    ["flag_pg","🇵🇬"],
    ["flag-ph","🇵🇭"],
    ["philippines","🇵🇭"],
    ["flag_ph","🇵🇭"],
    ["flag-pk","🇵🇰"],
    ["pakistan","🇵🇰"],
    ["flag_pk","🇵🇰"],
    ["flag-pl","🇵🇱"],
    ["poland","🇵🇱"],
    ["flag_pl","🇵🇱"],
    ["flag-pm","🇵🇲"],
    ["st_pierre_miquelon","🇵🇲"],
    ["flag_pm","🇵🇲"],
    ["flag-pn","🇵🇳"],
    ["pitcairn_islands","🇵🇳"],
    ["flag_pn","🇵🇳"],
    ["flag-pr","🇵🇷"],
    ["puerto_rico","🇵🇷"],
    ["flag_pr","🇵🇷"],
    ["flag-ps","🇵🇸"],
    ["palestinian_territories","🇵🇸"],
    ["flag_ps","🇵🇸"],
    ["flag-pt","🇵🇹"],
    ["portugal","🇵🇹"],
    ["flag_pt","🇵🇹"],
    ["flag-pw","🇵🇼"],
    ["palau","🇵🇼"],
    ["flag_pw","🇵🇼"],
    ["flag-py","🇵🇾"],
    ["paraguay","🇵🇾"],
    ["flag_py","🇵🇾"],
    ["flag-qa","🇶🇦"],
    ["qatar","🇶🇦"],
    ["flag_qa","🇶🇦"],
    ["flag-re","🇷🇪"],
    ["reunion","🇷🇪"],
    ["flag_re","🇷🇪"],
    ["flag-ro","🇷🇴"],
    ["romania","🇷🇴"],
    ["flag_ro","🇷🇴"],
    ["flag-rs","🇷🇸"],
    ["serbia","🇷🇸"],
    ["flag_rs","🇷🇸"],
    ["ru","🇷🇺"],
    ["flag-ru","🇷🇺"],
    ["flag_ru","🇷🇺"],
    ["russia","🇷🇺"],
    ["flag-rw","🇷🇼"],
    ["rwanda","🇷🇼"],
    ["flag_rw","🇷🇼"],
    ["flag-sa","🇸🇦"],
    ["saudi_arabia","🇸🇦"],
    ["flag_sa","🇸🇦"],
    ["flag-sb","🇸🇧"],
    ["solomon_islands","🇸🇧"],
    ["flag_sb","🇸🇧"],
    ["flag-sc","🇸🇨"],
    ["seychelles","🇸🇨"],
    ["flag_sc","🇸🇨"],
    ["flag-sd","🇸🇩"],
    ["sudan","🇸🇩"],
    ["flag_sd","🇸🇩"],
    ["flag-se","🇸🇪"],
    ["sweden","🇸🇪"],
    ["flag_se","🇸🇪"],
    ["flag-sg","🇸🇬"],
    ["singapore","🇸🇬"],
    ["flag_sg","🇸🇬"],
    ["flag-sh","🇸🇭"],
    ["st_helena","🇸🇭"],
    ["flag_sh","🇸🇭"],
    ["flag-si","🇸🇮"],
    ["slovenia","🇸🇮"],
    ["flag_si","🇸🇮"],
    ["flag-sj","🇸🇯"],
    ["svalbard_jan_mayen","🇸🇯"],
    ["flag_sj","🇸🇯"],
    ["flag-sk","🇸🇰"],
    ["slovakia","🇸🇰"],
    ["flag_sk","🇸🇰"],
    ["flag-sl","🇸🇱"],
    ["sierra_leone","🇸🇱"],
    ["flag_sl","🇸🇱"],
    ["flag-sm","🇸🇲"],
    ["san_marino","🇸🇲"],
    ["flag_sm","🇸🇲"],
    ["flag-sn","🇸🇳"],
    ["senegal","🇸🇳"],
    ["flag_sn","🇸🇳"],
    ["flag-so","🇸🇴"],
    ["somalia","🇸🇴"],
    ["flag_so","🇸🇴"],
    ["flag-sr","🇸🇷"],
    ["suriname","🇸🇷"],
    ["flag_sr","🇸🇷"],
    ["flag-ss","🇸🇸"],
    ["south_sudan","🇸🇸"],
    ["flag_ss","🇸🇸"],
    ["flag-st","🇸🇹"],
    ["sao_tome_principe","🇸🇹"],
    ["flag_st","🇸🇹"],
    ["flag-sv","🇸🇻"],
    ["el_salvador","🇸🇻"],
    ["flag_sv","🇸🇻"],
    ["flag-sx","🇸🇽"],
    ["sint_maarten","🇸🇽"],
    ["flag_sx","🇸🇽"],
    ["flag-sy","🇸🇾"],
    ["syria","🇸🇾"],
    ["flag_sy","🇸🇾"],
    ["flag-sz","🇸🇿"],
    ["swaziland","🇸🇿"],
    ["eswatini","🇸🇿"],
    ["flag_sz","🇸🇿"],
    ["flag-ta","🇹🇦"],
    ["tristan_da_cunha","🇹🇦"],
    ["flag_ta","🇹🇦"],
    ["flag-tc","🇹🇨"],
    ["turks_caicos_islands","🇹🇨"],
    ["flag_tc","🇹🇨"],
    ["flag-td","🇹🇩"],
    ["chad","🇹🇩"],
    ["flag_td","🇹🇩"],
    ["flag-tf","🇹🇫"],
    ["french_southern_territories","🇹🇫"],
    ["flag_tf","🇹🇫"],
    ["flag-tg","🇹🇬"],
    ["togo","🇹🇬"],
    ["flag_tg","🇹🇬"],
    ["flag-th","🇹🇭"],
    ["thailand","🇹🇭"],
    ["flag_th","🇹🇭"],
    ["flag-tj","🇹🇯"],
    ["tajikistan","🇹🇯"],
    ["flag_tj","🇹🇯"],
    ["flag-tk","🇹🇰"],
    ["tokelau","🇹🇰"],
    ["flag_tk","🇹🇰"],
    ["flag-tl","🇹🇱"],
    ["timor_leste","🇹🇱"],
    ["flag_tl","🇹🇱"],
    ["flag-tm","🇹🇲"],
    ["turkmenistan","🇹🇲"],
    ["flag_tm","🇹🇲"],
    ["flag-tn","🇹🇳"],
    ["tunisia","🇹🇳"],
    ["flag_tn","🇹🇳"],
    ["flag-to","🇹🇴"],
    ["tonga","🇹🇴"],
    ["flag_to","🇹🇴"],
    ["flag-tr","🇹🇷"],
    ["tr","🇹🇷"],
    ["flag_tr","🇹🇷"],
    ["turkey_tr","🇹🇷"],
    ["flag-tt","🇹🇹"],
    ["trinidad_tobago","🇹🇹"],
    ["flag_tt","🇹🇹"],
    ["flag-tv","🇹🇻"],
    ["tuvalu","🇹🇻"],
    ["flag_tv","🇹🇻"],
    ["flag-tw","🇹🇼"],
    ["taiwan","🇹🇼"],
    ["flag_tw","🇹🇼"],
    ["flag-tz","🇹🇿"],
    ["tanzania","🇹🇿"],
    ["flag_tz","🇹🇿"],
    ["flag-ua","🇺🇦"],
    ["ukraine","🇺🇦"],
    ["flag_ua","🇺🇦"],
    ["flag-ug","🇺🇬"],
    ["uganda","🇺🇬"],
    ["flag_ug","🇺🇬"],
    ["flag-um","🇺🇲"],
    ["us_outlying_islands","🇺🇲"],
    ["flag_um","🇺🇲"],
    ["flag-un","🇺🇳"],
    ["united_nations","🇺🇳"],
    ["flag_un","🇺🇳"],
    ["un","🇺🇳"],
    ["us","🇺🇸"],
    ["flag-us","🇺🇸"],
    ["flag_us","🇺🇸"],
    ["united_states","🇺🇸"],
    ["usa","🇺🇸"],
    ["flag-uy","🇺🇾"],
    ["uruguay","🇺🇾"],
    ["flag_uy","🇺🇾"],
    ["flag-uz","🇺🇿"],
    ["uzbekistan","🇺🇿"],
    ["flag_uz","🇺🇿"],
    ["flag-va","🇻🇦"],
    ["vatican_city","🇻🇦"],
    ["flag_va","🇻🇦"],
    ["flag-vc","🇻🇨"],
    ["st_vincent_grenadines","🇻🇨"],
    ["flag_vc","🇻🇨"],
    ["flag-ve","🇻🇪"],
    ["venezuela","🇻🇪"],
    ["flag_ve","🇻🇪"],
    ["flag-vg","🇻🇬"],
    ["british_virgin_islands","🇻🇬"],
    ["flag_vg","🇻🇬"],
    ["flag-vi","🇻🇮"],
    ["us_virgin_islands","🇻🇮"],
    ["flag_vi","🇻🇮"],
    ["flag-vn","🇻🇳"],
    ["vietnam","🇻🇳"],
    ["flag_vn","🇻🇳"],
    ["flag-vu","🇻🇺"],
    ["vanuatu","🇻🇺"],
    ["flag_vu","🇻🇺"],
    ["flag-wf","🇼🇫"],
    ["wallis_futuna","🇼🇫"],
    ["flag_wf","🇼🇫"],
    ["flag-ws","🇼🇸"],
    ["samoa","🇼🇸"],
    ["flag_ws","🇼🇸"],
    ["flag-xk","🇽🇰"],
    ["kosovo","🇽🇰"],
    ["flag_xk","🇽🇰"],
    ["flag-ye","🇾🇪"],
    ["yemen","🇾🇪"],
    ["flag_ye","🇾🇪"],
    ["flag-yt","🇾🇹"],
    ["mayotte","🇾🇹"],
    ["flag_yt","🇾🇹"],
    ["flag-za","🇿🇦"],
    ["south_africa","🇿🇦"],
    ["flag_za","🇿🇦"],
    ["flag-zm","🇿🇲"],
    ["zambia","🇿🇲"],
    ["flag_zm","🇿🇲"],
    ["flag-zw","🇿🇼"],
    ["zimbabwe","🇿🇼"],
    ["flag_zw","🇿🇼"],
    ["flag-england","🏴󠁧󠁢󠁥󠁮󠁧󠁿"],
    ["england","🏴󠁧󠁢󠁥󠁮󠁧󠁿"],
    ["flag_gbeng","🏴󠁧󠁢󠁥󠁮󠁧󠁿"],
    ["flag-scotland","🏴󠁧󠁢󠁳󠁣󠁴󠁿"],
    ["scotland","🏴󠁧󠁢󠁳󠁣󠁴󠁿"],
    ["flag_gbsct","🏴󠁧󠁢󠁳󠁣󠁴󠁿"],
    ["flag-wales","🏴󠁧󠁢󠁷󠁬󠁳󠁿"],
    ["wales","🏴󠁧󠁢󠁷󠁬󠁳󠁿"],
    ["flag_gbwls","🏴󠁧󠁢󠁷󠁬󠁳󠁿"]
  ];

  const MAX_ROWS = 6;

  /* ---------- fuzzy matcher ---------- */

  function score(query, code) {
    const q = query.toLowerCase();
    const c = code.toLowerCase();
    if (c === q) return 1000;
    if (c.startsWith(q)) return 500 - (c.length - q.length);
    const idx = c.indexOf(q);
    if (idx >= 0) return 200 - idx * 2 - (c.length - q.length);
    let i = 0, j = 0, firstIdx = -1, gaps = 0, lastJ = -1;
    while (i < q.length && j < c.length) {
      if (q.charCodeAt(i) === c.charCodeAt(j)) {
        if (firstIdx === -1) firstIdx = j;
        if (lastJ !== -1 && j - lastJ > 1) gaps += (j - lastJ - 1);
        lastJ = j;
        i++;
      }
      j++;
    }
    if (i === q.length) return 50 - firstIdx - gaps * 2 - (c.length - q.length) * 0.5;
    return -Infinity;
  }

  function search(query) {
    if (!query) return [];
    const results = [];
    for (const [code, emoji] of DB) {
      const s = score(query, code);
      if (s > -Infinity) results.push({ code, emoji, score: s });
    }
    results.sort((a, b) => b.score - a.score || a.code.length - b.code.length);
    return results.slice(0, MAX_ROWS);
  }

  /* ---------- text measurement ----------
     Canvas measureText gives us the pixel width of the substring before `:`,
     which is what we need to anchor the picker under the active query. */

  const measureCanvas = document.createElement('canvas');
  const measureCtx = measureCanvas.getContext('2d');
  let cachedFont = '';

  function measureTextWidth(text) {
    if (!cachedFont) {
      const cs = getComputedStyle(input);
      cachedFont = `${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
      measureCtx.font = cachedFont;
    }
    return measureCtx.measureText(text).width;
  }

  function positionPicker(q) {
    // Anchor the picker directly under the line containing `:` — not the
    // bottom of the textarea. Counts newlines in the text before `:` to
    // figure out the line index, then positions Y at the bottom of that line.
    const anchor = picker.parentElement;
    if (!anchor) return;
    const cs = getComputedStyle(input);
    const padLeft = parseFloat(cs.paddingLeft);
    const padRight = parseFloat(cs.paddingRight);
    const rtl = cs.direction === 'rtl';
    const padTop = parseFloat(cs.paddingTop);
    const lineHeight = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.55;
    const inputRect = input.getBoundingClientRect();
    const anchorRect = anchor.getBoundingClientRect();
    // Mobile breakpoints apply `transform: scale()` to .picker-anchor (and to
    // the sibling .carousel). getBoundingClientRect returns post-transform
    // viewport px, but getComputedStyle padding / canvas measureText /
    // picker.offsetHeight are all unscaled CSS px. Normalize the rect-derived
    // offsets to unscaled CSS px so every value below is in the same coord
    // space. The picker is positioned via style.left/top in CSS px inside the
    // scaled anchor, so the browser scales those coords on render — meaning
    // we should write them at *unscaled* magnitudes.
    const scaleX = (anchor.offsetWidth && anchorRect.width / anchor.offsetWidth) || 1;
    const scaleY = (anchor.offsetHeight && anchorRect.height / anchor.offsetHeight) || 1;

    const textBefore = input.value.slice(0, q.start);
    const lineIndex = (textBefore.match(/\n/g) || []).length;
    const lastNewline = textBefore.lastIndexOf('\n');
    const currentLineText = textBefore.slice(lastNewline + 1);

    const inputOffsetX = (inputRect.left - anchorRect.left) / scaleX;
    const inputOffsetY = (inputRect.top - anchorRect.top) / scaleY;

    // In an RTL field the text is right-aligned, so the caret (and the trailing
    // `:query`) sits at the left end of the run: measure from the right edge in.
    // LTR keeps the original measure-from-the-left math.
    const lineWidth = measureTextWidth(currentLineText);
    const colonX = rtl
      ? inputOffsetX + (inputRect.width / scaleX) - padRight - lineWidth
      : inputOffsetX + padLeft + lineWidth - (input.scrollLeft || 0);
    const lineBaseY = inputOffsetY + padTop + lineIndex * lineHeight - (input.scrollTop || 0);
    const colonBottom = lineBaseY + lineHeight;
    const colonTop = lineBaseY;

    // If placing the picker below the line would push it off the bottom of
    // the hero-card, place it above the line instead — mirrors the real app,
    // which flips the picker when it would clip below the screen. Use the
    // unscaled anchor height so this check works at any scale factor.
    const anchorHeight = anchor.offsetHeight || anchorRect.height;
    const pickerHeight = picker.offsetHeight || 280;
    const margin = 6;
    let pickerTop;
    if (colonBottom + margin + pickerHeight > anchorHeight) {
      pickerTop = colonTop - margin - pickerHeight;
    } else {
      pickerTop = colonBottom + margin;
    }

    picker.style.left = `${Math.max(8, colonX - 4)}px`;
    picker.style.top = `${pickerTop}px`;
  }

  /* ---------- rendering ---------- */

  let activeIndex = 0;
  let currentMatches = [];

  function rowId(i) { return 'picker-row-' + i; }

  function renderRow(code, emoji, query, active, i) {
    const li = document.createElement('li');
    li.id = rowId(i);
    li.className = 'picker-row' + (active ? ' active' : '');
    li.setAttribute('role', 'option');
    li.setAttribute('aria-selected', active ? 'true' : 'false');
    const idx = code.toLowerCase().indexOf(query.toLowerCase());
    let codeHtml;
    if (idx === -1 || !query) {
      codeHtml = `:${escapeHtml(code)}:`;
    } else {
      const a = code.slice(0, idx);
      const b = code.slice(idx, idx + query.length);
      const c = code.slice(idx + query.length);
      codeHtml = `:${escapeHtml(a)}<span class="match">${escapeHtml(b)}</span>${escapeHtml(c)}:`;
    }
    li.innerHTML =
      `<span class="px-emoji">${emoji}</span>` +
      `<span class="px-code">${codeHtml}</span>`;
    return li;
  }

  function escapeHtml(s) {
    return s.replace(/[&<>"']/g, (c) =>
      ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
  }

  function renderPicker(query, matches) {
    list.innerHTML = '';
    matches.forEach((m, i) => {
      const row = renderRow(m.code, m.emoji, query, i === activeIndex, i);
      row.addEventListener('mouseenter', () => {
        activeIndex = i;
        updateSelection();
      });
      row.addEventListener('mousedown', (e) => {
        e.preventDefault();
        activeIndex = i;
        commit();
      });
      list.appendChild(row);
    });
    updateActiveDescendant();
  }

  function updateSelection() {
    const rows = list.querySelectorAll('.picker-row');
    rows.forEach((r, i) => {
      const isActive = i === activeIndex;
      r.classList.toggle('active', isActive);
      r.setAttribute('aria-selected', isActive ? 'true' : 'false');
    });
    updateActiveDescendant();
  }

  function updateActiveDescendant() {
    // Reflect the active row on whichever demo input currently has focus,
    // so AT can follow the highlight without focus moving off the textarea.
    inputs.forEach((el) => {
      if (document.activeElement === el && currentMatches.length) {
        el.setAttribute('aria-controls', 'picker-list');
        el.setAttribute('aria-activedescendant', rowId(activeIndex));
      } else {
        el.removeAttribute('aria-controls');
        el.removeAttribute('aria-activedescendant');
      }
    });
  }

  function showPicker() {
    void picker.offsetWidth;
    picker.classList.add('show');
    picker.setAttribute('aria-hidden', 'false');
  }

  function hidePicker() {
    picker.classList.remove('show');
    picker.setAttribute('aria-hidden', 'true');
    activeIndex = 0;
    currentMatches = [];
    list.innerHTML = '';   // drop stale options from the a11y tree entirely
    updateActiveDescendant();
  }

  /* ---------- input → picker pipeline ---------- */

  function activeQuery(value, caret) {
    // Shortcode chars: letters/digits/_/- — hyphen is essential for the
    // hundreds of `flag-<cc>` codes and others like `star-struck`.
    const SHORTCODE_CHAR = /[A-Za-z0-9_-]/;
    let start = -1;
    for (let i = caret - 1; i >= 0; i--) {
      const ch = value[i];
      if (ch === ':') { start = i; break; }
      if (!SHORTCODE_CHAR.test(ch)) return null;
    }
    if (start === -1) return null;
    let end = caret;
    let exact = false;
    while (end < value.length) {
      const ch = value[end];
      if (ch === ':') { exact = true; break; }
      if (!SHORTCODE_CHAR.test(ch)) break;
      end++;
    }
    const query = value.slice(start + 1, end);
    // Don't treat `:-)` / `:-(` / `:-D` as a shortcode — the leading hyphen
    // means the user is typing an emoticon, not a shortcode. `:flag-us:` is
    // still fine (hyphen is mid-query, not leading).
    if (query.startsWith('-')) return null;
    return { start, end, query, exact };
  }

  function handleInput() {
    const value = input.value;
    const focused = document.activeElement === input;
    const caret = focused ? (input.selectionStart ?? value.length) : value.length;
    const q = activeQuery(value, caret);
    if (!q || !q.query) { hidePicker(); return; }

    const matches = search(q.query);
    if (matches.length === 0) { hidePicker(); return; }

    if (q.exact && matches[0].code.toLowerCase() === q.query.toLowerCase()) {
      const before = value.slice(0, q.start);
      const after = value.slice(q.end + 1);
      input.value = before + matches[0].emoji + after;
      const newCaret = (before + matches[0].emoji).length;
      if (focused) input.setSelectionRange(newCaret, newCaret);
      hidePicker();
      return;
    }

    currentMatches = matches;
    activeIndex = Math.min(activeIndex, matches.length - 1);
    if (activeIndex < 0) activeIndex = 0;
    positionPicker(q);
    renderPicker(q.query, matches);
    showPicker();
  }

  function commit() {
    if (!currentMatches.length) return;
    const value = input.value;
    const caret = input.selectionStart ?? value.length;
    const q = activeQuery(value, caret);
    if (!q) { hidePicker(); return; }
    const emoji = currentMatches[activeIndex].emoji;
    const before = value.slice(0, q.start);
    const after = value.slice(q.end + (q.exact ? 1 : 0));
    input.value = before + emoji + after;
    const newCaret = (before + emoji).length;
    input.setSelectionRange(newCaret, newCaret);
    hidePicker();
  }

  /* ---------- keyboard (document-delegated across all .demo-input) ---------- */

  function isDemoInput(el) { return el && el.classList && el.classList.contains('demo-input'); }

  document.addEventListener('input', (e) => {
    if (!isDemoInput(e.target)) return;
    input = e.target;
    stopAutoplay();
    handleInput();
  });

  document.addEventListener('keydown', (e) => {
    if (!isDemoInput(e.target)) return;
    input = e.target;
    if (e.key === 'ArrowDown' && currentMatches.length) {
      e.preventDefault();
      activeIndex = (activeIndex + 1) % currentMatches.length;
      updateSelection();
    } else if (e.key === 'ArrowUp' && currentMatches.length) {
      e.preventDefault();
      activeIndex = (activeIndex - 1 + currentMatches.length) % currentMatches.length;
      updateSelection();
    } else if ((e.key === 'Enter' || e.key === 'Tab') && currentMatches.length) {
      e.preventDefault();
      commit();
    } else if (e.key === 'Escape' && picker.classList.contains('show')) {
      // Only swallow Escape when the picker is actually showing — otherwise
      // we'd break the textarea's native Escape behavior + host-page handlers.
      e.preventDefault();
      hidePicker();
    }
  });

  // Autoplay resume timer: when the user blurs the textarea, wait 1s and
  // restart the carousel. Cancelled if they re-focus before the timer fires.
  let resumeTimer = null;
  function cancelResume() {
    if (resumeTimer) { clearTimeout(resumeTimer); resumeTimer = null; }
  }

  document.addEventListener('focusin', (e) => {
    if (!isDemoInput(e.target)) return;
    const prevInput = input;
    input = e.target;
    cancelResume();
    if (autoplay) {
      stopAutoplay();
      input.value = '';
      hidePicker();
    } else if (input !== prevInput) {
      // Moving focus between demo inputs drops any picker rendered for the
      // previous input — otherwise the new input's aria-activedescendant
      // would reference rows describing the old input's query.
      hidePicker();
    }
    // Each app's textarea may use a different font (terminal is monospace).
    cachedFont = '';
    updateActiveDescendant();
  });

  document.addEventListener('focusout', (e) => {
    if (!isDemoInput(e.target)) return;
    cancelResume();
    // Don't schedule a resume on a hidden tab — the timer would tick while
    // invisible and start autoplay against a backgrounded page.
    if (document.hidden) return;
    resumeTimer = setTimeout(() => {
      resumeTimer = null;
      if (document.hidden) return;
      // Only resume if user hasn't returned to an input in the meantime.
      if (!inputs.some((el) => document.activeElement === el)) {
        autoplayLoop();
      }
    }, 1000);
  });

  /* ---------- autoplay ----------
     Each scene cycles to the next app in the carousel, types a sentence with
     a `:query`, the picker pops in, the emoji replaces it. */

  let autoplay = true;
  let autoplayToken = 0;

  function stopAutoplay() {
    autoplay = false;
    autoplayToken++;
  }

  // reduceMotion is declared above setActiveApp.

  /* ---------- "live" timestamps in the mocks ----------
     Make the previews feel current instead of frozen on May 23. Populate:
       - Terminal `Last login: …` line
       - iMessage meta `Today · H:MM AM/PM`
       - TextEdit "Design Review — <Mon D>" prefill (in the scenes table below)
     All read from `new Date()` at script load — good enough; the page isn't
     long-lived. */
  const _now = new Date();
  const _days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const _pad = (n) => String(n).padStart(2, '0');
  function formatTime12(d) {
    let h = d.getHours();
    const m = _pad(d.getMinutes());
    const ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12; if (h === 0) h = 12;
    return `${h}:${m} ${ampm}`;
  }
  function formatTermLogin(d) {
    return `${_days[d.getDay()]} ${_months[d.getMonth()]} ${_pad(d.getDate())} ${_pad(d.getHours())}:${_pad(d.getMinutes())}:${_pad(d.getSeconds())}`;
  }
  // Terminal "Last login" stamp: an hour to three hours back so it looks like
  // a real session that's been idle a while.
  const _lastLogin = new Date(_now.getTime() - (60 + Math.floor(Math.random() * 120)) * 60000);
  const termLoginEl = document.querySelector('.term-login');
  if (termLoginEl) termLoginEl.textContent = `Last login: ${formatTermLogin(_lastLogin)} on ttys001`;
  const imMetaTimeEl = document.querySelector('.im-meta-time');

  // i18n hooks: scene prose and the iMessage timestamp are localized through
  // window.MojitoI18n (i18n.js). The Terminal scene stays English — it's a
  // literal git command — and `:query` shortcodes always match the English
  // demo DB, so only the surrounding before/after prose is translated.
  const I18N = window.MojitoI18n;
  const tr = (key, fallback) => (I18N && I18N.t) ? I18N.t(key, fallback) : fallback;
  const curLocale = () => (I18N && I18N.locale) ? I18N.locale : 'en';

  function localizedTime(d) {
    try { return new Intl.DateTimeFormat(curLocale(), { hour: 'numeric', minute: '2-digit' }).format(d); }
    catch (e) { return formatTime12(d); }
  }
  function localizedDocDate(d) {
    try { return new Intl.DateTimeFormat(curLocale(), { month: 'short', day: 'numeric' }).format(d); }
    catch (e) { return `${_months[d.getMonth()]} ${d.getDate()}`; }
  }
  function refreshIMessageTime() {
    if (imMetaTimeEl) imMetaTimeEl.textContent = `${tr('demo.imessage.today', 'Today')} · ${localizedTime(_now)}`;
  }

  // Each scene targets one app and uses a UNIQUE emoji (no repeats across the cycle).
  // App indices: 0=TextEdit, 1=iMessage, 2=Terminal, 3=Mastodon, 4=Reminders.
  // `prefilled`: text already in the textarea when the slide arrives (not typed).
  function buildScenes() {
    const docTemplate = tr('demo.scene.doc',
      'Design Review — {date}\n\nPicker should fade in on first show. Team agreed.\n\nTo-do:\n- Add fade-in flag');
    return [
      {
        app: 0,
        prefilled: docTemplate.replace('{date}', localizedDocDate(_now)),
        before: tr('demo.scene.deadline', '\n- Hit deadline '), query: 'fire', after: '',
      },
      { app: 1, before: tr('demo.scene.soon', 'see you soon '),               query: 'wave',   after: '' },
      { app: 2, before: 'git commit -m "fix the ',                            query: 'bug',    after: '"' },
      { app: 3, before: tr('demo.scene.shipped', 'Just shipped a new app '),  query: 'rocket', after: '' },
      { app: 4, before: tr('demo.scene.pickup', 'Pick up '),                  query: 'gift',   after: tr('demo.scene.formom', ' for mom') },
    ];
  }
  let scenes = buildScenes();

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const wait = (ms) => sleep(reduceMotion ? 0 : ms);
  const jitter = (n, s = 40) => Math.max(28, n + (Math.random() - 0.5) * s);

  async function typeChars(prefix, chars, perCharMs, token) {
    let typed = prefix;
    for (const ch of chars) {
      if (token !== autoplayToken) return null;
      typed += ch;
      input.value = typed;
      handleInput();
      await wait(jitter(perCharMs));
    }
    return typed;
  }

  async function typeScene(scene, token) {
    // ~20% faster than before: before/after at 52ms/char, query at 72ms/char.
    const prefilled = scene.prefilled || '';
    let typed = await typeChars(prefilled, scene.before, 52, token);
    if (typed === null) return false;

    typed = await typeChars(typed, ':' + scene.query, 72, token);
    if (typed === null) return false;

    await wait(360);
    if (token !== autoplayToken) return false;

    if (currentMatches.length) {
      const emoji = currentMatches[0].emoji;
      typed = prefilled + scene.before + emoji;
      input.value = typed;
      hidePicker();
      await wait(140);
    }
    if (token !== autoplayToken) return false;

    typed = await typeChars(typed, scene.after, 52, token);
    if (typed === null) return false;

    await wait(1300);
    return true;
  }

  // iMessage: turn the typed message into a sent bubble after a beat.
  function resetIMessage() {
    const imApp = apps[1];
    if (!imApp) return;
    imApp.querySelectorAll('.bubble.sent').forEach((b) => b.remove());
    const compose = imApp.querySelector('.demo-input');
    if (compose) compose.value = '';
  }

  function sendIMessage() {
    const imApp = apps[1];
    if (!imApp) return;
    const compose = imApp.querySelector('.demo-input');
    const bubbles = imApp.querySelector('.bubbles');
    if (!compose || !bubbles) return;
    const text = compose.value.trim();
    if (!text) return;
    const sent = document.createElement('div');
    sent.className = 'bubble sent is-new';
    sent.textContent = text;
    bubbles.appendChild(sent);
    compose.value = '';
    // Strip the animation class after it plays so the bubble doesn't re-animate
    // if its layout changes later.
    setTimeout(() => sent.classList.remove('is-new'), 600);
  }

  function clearAllInputs() {
    inputs.forEach((el) => { el.value = ''; });
  }

  async function autoplayLoop() {
    const token = ++autoplayToken;
    autoplay = true;
    let i = 0;
    while (token === autoplayToken && autoplay) {
      const scene = scenes[i++ % scenes.length];
      hidePicker();
      // iMessage: clear any previously-sent bubbles before sliding in.
      if (scene.app === 1) resetIMessage();
      setActiveApp(scene.app);
      input.value = scene.prefilled || '';
      await wait(580); // slightly longer than the 0.55s CSS transition
      if (token !== autoplayToken) return;
      const ok = await typeScene(scene, token);
      if (!ok) return;
      // iMessage: actually "send" the message after the scene completes.
      if (scene.app === 1) {
        await wait(280);
        if (token !== autoplayToken) return;
        sendIMessage();
        await wait(1050);
      }
      clearAllInputs();
      hidePicker();
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      autoplayToken++;
      // Also cancel any pending blur→resume timer so it doesn't fire while
      // the tab is hidden and kick off a new autoplayLoop on an invisible page.
      cancelResume();
    } else if (!inputs.some((el) => document.activeElement === el)) {
      // Returning to the tab with no input focused: resume autoplay even if
      // a prior interaction had flipped `autoplay` off. Otherwise a single
      // click + blur + tab-switch leaves the demo permanently silent because
      // the focusout resume timer was cancelled by the visibility-hidden
      // branch above and never re-armed.
      autoplayLoop();
    }
  });

  window.addEventListener('resize', () => {
    cachedFont = '';
    // Apps are positioned relative to the hero-card via CSS top:50%; left:50%,
    // so resize re-centers them automatically — no carousel math needed here.

    if (picker.classList.contains('show')) {
      const value = input.value;
      const caret = document.activeElement === input
        ? (input.selectionStart ?? value.length)
        : value.length;
      const q = activeQuery(value, caret);
      if (q) positionPicker(q);
    }
  });

  function startDemo() {
    if (reduceMotion) {
      autoplay = false;
      setActiveApp(0);
      input.value = tr('demo.fallback', "Don't forget the :tada");
      handleInput();
    } else {
      autoplayLoop();
    }
  }

  // Rebuild scenes + restart whenever the visitor switches languages.
  function relocalizeDemo() {
    scenes = buildScenes();
    refreshIMessageTime();
    if (reduceMotion) {
      input.value = tr('demo.fallback', "Don't forget the :tada");
      handleInput();
    } else {
      autoplayLoop(); // bumps autoplayToken → cleanly restarts with new scenes
    }
  }

  // Wait for i18n to settle so the first scenes build in the active locale.
  if (I18N && I18N.ready && typeof I18N.ready.then === 'function') {
    I18N.ready.then(() => { scenes = buildScenes(); refreshIMessageTime(); startDemo(); });
    if (I18N.onChange) I18N.onChange(relocalizeDemo);
  } else {
    refreshIMessageTime();
    startDemo();
  }

  /* ---------- easter egg: drag "Website" folder to trash to crash the site.
     Uses HTML5 drag-and-drop, no touch support (mobile is autoplay-only and
     drag-and-drop isn't a native touch gesture anyway). On drop, we stop the
     autoplay loop, play a short synthesized "death chime" via Web Audio, and
     show the Sad Mac overlay (#sadmac). Click anywhere on the overlay to
     "reboot": we fade it out and restart the demo in place rather than
     reloading the page, so the separately-animated discovery banner
     (#achievement) survives to run out its own timer. */
  const folder = document.getElementById('desktop-folder');
  const trash = document.getElementById('desktop-trash');
  const sadmac = document.getElementById('sadmac');

  if (folder && trash && sadmac) {
    folder.addEventListener('dragstart', (e) => {
      folder.classList.add('is-dragging');
      if (e.dataTransfer) {
        e.dataTransfer.effectAllowed = 'move';
        // Firefox refuses to start a drag unless something is in dataTransfer.
        try { e.dataTransfer.setData('text/plain', 'website'); } catch (_) {}

        // Build a macOS Finder-style drag image: folder icon with its full
        // drop-shadow intact (the browser would otherwise clip the source
        // element's shadow at the element box), plus a blue accent pill for
        // the label. Element must be in the DOM and visible for the browser
        // to snapshot it; we park it offscreen and remove it on the next
        // tick (the snapshot is captured synchronously).
        const ghost = document.createElement('div');
        ghost.className = 'drag-ghost';
        const img = document.createElement('img');
        img.className = 'drag-ghost-img';
        img.src = 'folder.png?v=2';
        img.srcset = 'folder.png?v=2 1x, folder@2x.png?v=2 2x';
        img.width = 72; img.height = 72; img.alt = '';
        const label = document.createElement('span');
        label.className = 'drag-ghost-label';
        label.textContent = 'Website';
        ghost.appendChild(img);
        ghost.appendChild(label);
        document.body.appendChild(ghost);
        // Offset roughly centers the drag image on the cursor (icon center).
        e.dataTransfer.setDragImage(ghost, 58, 40);
        setTimeout(() => ghost.remove(), 0);
      }
    });
    folder.addEventListener('dragend', () => {
      folder.classList.remove('is-dragging');
      trash.classList.remove('is-dropzone');
    });

    // dragenter/dragover must preventDefault to mark the element as a drop
    // target; otherwise the browser won't fire `drop`.
    const allowDrop = (e) => {
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
      trash.classList.add('is-dropzone');
    };
    trash.addEventListener('dragenter', allowDrop);
    trash.addEventListener('dragover', allowDrop);
    trash.addEventListener('dragleave', (e) => {
      // Only un-highlight when we actually leave the trash, not when crossing
      // over its child elements (dragleave fires on every child boundary).
      if (e.target === trash || !trash.contains(e.relatedTarget)) {
        trash.classList.remove('is-dropzone');
      }
    });
    trash.addEventListener('drop', (e) => {
      e.preventDefault();
      trash.classList.remove('is-dropzone');
      folder.classList.remove('is-dragging');
      crashTheSite();
    });
  }

  function crashTheSite() {
    stopAutoplay();
    // Hide the active app + picker instantly so the "crash" feels abrupt
    // — even before the overlay fades in.
    if (picker) picker.classList.remove('show');
    // Crash half first: death chime + Sad Mac overlay. The chime runs
    // ~1s end-to-end (440 → 277 → 130 Hz square pulses).
    playDeathChime();
    if (sadmac) {
      sadmac.setAttribute('aria-hidden', 'false');
      // next frame so the transition runs
      requestAnimationFrame(() => sadmac.classList.add('is-on'));
      // "Reboot" in place instead of window.location.reload(): the banner is
      // a separate, independently-animated element and a full reload would
      // tear it down mid-flight. Fade the overlay out and restart the demo so
      // the banner survives on its own auto-dismiss timer.
      sadmac.addEventListener('click', () => {
        sadmac.classList.remove('is-on');        // 0.12s opacity fade-out
        sadmac.setAttribute('aria-hidden', 'true');
        if (reduceMotion) {
          setActiveApp(0);
          input.value = "Don't forget the :tada";
          handleInput();
        } else {
          autoplayLoop();
        }
      }, { once: true });
    }
    // Discovery half: once the chime has cleared, the banner scale-pops in
    // and the cheerful fanfare plays on its own. Sequencing this way keeps
    // the two sound effects from stepping on each other and lets the
    // "you found an egg" reveal land after the joke crash.
    const CHIME_MS = 1100;
    setTimeout(() => {
      showAchievementBanner();
      playDiscoveryFanfare();
    }, CHIME_MS);
  }

  // Ascending C-major arpeggio (C5 → E5 → G5) played as short square-wave
  // pulses with tiny attack/release envelopes to de-click the edges.
  // Mirrors `Sources/Mojito/App/DiscoveryFanfare.swift` — same notes,
  // durations, and master gain so the web "discovery" sounds the same as
  // the app's.
  function playDiscoveryFanfare() {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      const ctx = new Ctx();
      const now = ctx.currentTime;
      const notes = [
        { f: 523.25, t: 0.000, d: 0.09 },
        { f: 659.25, t: 0.115, d: 0.09 },
        { f: 783.99, t: 0.230, d: 0.16 },
      ];
      const master = ctx.createGain();
      master.gain.value = 0.06;
      master.connect(ctx.destination);
      notes.forEach((n) => {
        const osc = ctx.createOscillator();
        const g = ctx.createGain();
        osc.type = 'square';
        osc.frequency.setValueAtTime(n.f, now + n.t);
        g.gain.setValueAtTime(0, now + n.t);
        g.gain.linearRampToValueAtTime(1, now + n.t + 0.005);
        g.gain.setValueAtTime(1, now + n.t + n.d - 0.020);
        g.gain.linearRampToValueAtTime(0, now + n.t + n.d);
        osc.connect(g).connect(master);
        osc.start(now + n.t);
        osc.stop(now + n.t + n.d + 0.02);
      });
      setTimeout(() => { try { ctx.close(); } catch (_) {} }, 1200);
    } catch (_) { /* no audio, no problem */ }
  }

  // Scale-pop the banner in, hold for 3.5s, then scale it back out. Times
  // match the in-app AchievementBanner (3.5s hold, ~0.3s exit). The CSS
  // does the actual animation; this just toggles classes.
  function showAchievementBanner() {
    const el = document.getElementById('achievement');
    if (!el) return;
    el.setAttribute('aria-hidden', 'false');
    el.classList.remove('is-off');
    requestAnimationFrame(() => el.classList.add('is-on'));
    setTimeout(() => {
      el.classList.remove('is-on');
      el.classList.add('is-off');
      setTimeout(() => {
        el.setAttribute('aria-hidden', 'true');
        el.classList.remove('is-off');
      }, 300);
    }, 3500);
  }

  // Classic-Mac-style death chime — a short, harsh descending square-wave
  // motif. Synthesized so we don't have to ship an audio file. Best-effort:
  // silently bails if Web Audio is unavailable or blocked.
  function playDeathChime() {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      const ctx = new Ctx();
      const now = ctx.currentTime;
      // Three descending notes, square wave, short envelope each.
      const notes = [
        { f: 440, t: 0.00, d: 0.18 },
        { f: 277, t: 0.18, d: 0.22 },
        { f: 130, t: 0.42, d: 0.55 },
      ];
      const master = ctx.createGain();
      master.gain.value = 0.18;
      master.connect(ctx.destination);
      notes.forEach((n) => {
        const osc = ctx.createOscillator();
        const g = ctx.createGain();
        osc.type = 'square';
        osc.frequency.setValueAtTime(n.f, now + n.t);
        g.gain.setValueAtTime(0, now + n.t);
        g.gain.linearRampToValueAtTime(1, now + n.t + 0.01);
        g.gain.exponentialRampToValueAtTime(0.001, now + n.t + n.d);
        osc.connect(g).connect(master);
        osc.start(now + n.t);
        osc.stop(now + n.t + n.d + 0.02);
      });
      // Close the context after the chime finishes.
      setTimeout(() => { try { ctx.close(); } catch (_) {} }, 1500);
    } catch (_) { /* no audio, no problem */ }
  }
})();
