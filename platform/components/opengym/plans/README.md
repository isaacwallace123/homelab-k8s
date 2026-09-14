# Candiac gym plan

Import **[candiac-ppl-upper-lower.opengym.json](candiac-ppl-upper-lower.opengym.json)**
into each person's own openGym profile. The same routines work for both of you;
starting weights and progression are individual.

Assumptions: beginners or returning lifters aiming for muscle and general strength,
with no known injuries or movement restrictions. Aim for roughly 50-65 minutes per
session, including warm-up; sharing equipment may take longer. Try this for 6-8 weeks,
then review your logs, recovery, and exercise preferences.

## Import

1. Open [your openGym instance](https://fitness.isaacwallace.dev) and sign in.
2. Go to **Plan**, then the **Share your plan** icon at the top right.
3. Choose **Import a plan file** and select the JSON file.
4. The preview should show **5 routines, 28 exercises, 5 scheduled days**, with no
   dropped exercises. The exercise count includes movements repeated on different days.
5. Enable **Use this weekly schedule**, then choose **Add to my plan**.

The schedule switch replaces your weekday assignments and makes Thursday and Sunday
rest days. Existing routines and workout history remain. Import once per profile:
importing again adds another copy of the routines.

### Set the time separately

In **Settings > Notifications**, enable notifications and **Workout day reminder**,
then set **Reminder time** to **21:45**. Check the detected timezone is
**America/Toronto**. On an iPhone, use the app added to the Home Screen for push
notifications. Repeat in your friend's profile.

The plan format carries weekday assignments, but no reminder settings. The `21:45`
in the routine names is a label; it does not schedule a notification.

## Your week

Every training session starts at **9:45 p.m. Candiac local time**. Rest days have no
lifting session; an easy walk is optional if you still want to keep the nightly habit.

| Day | Focus | Exercises in order: work sets x reps |
| --- | --- | --- |
| Monday | Push | DB bench 3x8-12; incline DB bench 2x8-12; seated DB shoulder press 2x8-12; lateral raise 2x12-15; cable fly 2x10-15; rope pushdown 2x10-15 |
| Tuesday | Pull | Lat pulldown 3x8-12; seated cable row 3x8-12; reverse pec deck 2x12-15; DB curl 2x10-15; hammer curl 2x10-15 |
| Wednesday | Legs | Goblet squat 3x8-12; DB Romanian deadlift 2x8-12; seated leg curl 2x10-15; leg extension 2x10-15; standing DB calf raise 2x12-15; floor crunch 2x10-15 |
| Thursday | Rest | No lifting |
| Friday | Upper | Incline DB bench 3x8-12; seated cable row 3x8-12; lat pulldown 2x8-12; lateral raise 2x12-15; DB curl 2x10-15; rope pushdown 2x10-15 |
| Saturday | Lower | DB Romanian deadlift 3x8-12; leg press 3x8-12; seated leg curl 2x10-15; standing DB calf raise 3x12-15; floor crunch 2x10-15 |
| Sunday | Rest | No lifting |

DB means dumbbell. Counts above exclude the warm-up rows already included in the file.
The upper/lower sessions give the major muscle groups a second exposure each week.

## Start here tonight

- **Weeks 1-2:** reduce every 3-set exercise to 2 work sets. Keep the 2-set exercises
  at 2. Edit the routine or remove the extra work row; never mark an unperformed set
  complete. Add the third sets back only when recovering comfortably.
- Walk or cycle easily for 5 minutes. Use the planned warm-up rows for light ramp-up
  sets, adjusting their suggested weights to equipment you can actually use.
- Choose weights that let you perform the rep range with **2-3 more clean reps left**
  when you stop. That is "2-3 reps in reserve" (RIR). Each person chooses separately.
- Rest timers are included: 2-2.5 minutes for larger lifts, 75-90 seconds for most
  smaller exercises, and 60 seconds for crunches and warm-ups. Take longer if needed.
- Alternate sets with your friend, but measure your own rest from the end of your set.
  Keep the session near an hour; if time is short, skip the last accessory exercise.
- Use the exercise notes for technique cues and substitutions. Get a staff walkthrough
  for unfamiliar machines and the hip hinge. Stop a movement that causes sharp pain.

## Progress and track

Loaded exercises use **double progression**: add reps within the prescribed range,
then increase weight once every work set reaches its upper limit with controlled form
and 2-3 reps still available. For example, build 3x8 toward 3x12, then take the smallest
practical weight increase and work back up from about 8 reps.

OpenGym's suggestions do not assess your technique or use your RIR rating. Override a
suggestion if it would require grinding or exceed the equipment's smallest sensible
step. Default jumps can be large for dumbbells: after choosing kg or lb, set each
exercise's progression increment to suit the equipment. The file leaves increments
and starting weights unset so each profile can configure its own.

Log the **weight of one dumbbell** for paired dumbbell exercises, and one stack for
the two-cable fly. Goblet squat uses one dumbbell. For leg press, consistently log
added plates and note the machine/sled. Machine numbers are only comparable on the
same machine. Switch units in Settings to match the equipment labels before logging.

Floor crunches have automatic progression off: work toward 2x15 controlled reps.
Log only reps actually completed. If you substitute an exercise, swap its catalogue
entry too, so its history and muscle tracking stay accurate.

Track weight, reps, and completed work sets every session; add RIR if useful. If you
track body weight, use similar conditions each time, such as in the morning, and
compare trends rather than single readings. If soreness or falling performance keeps
carrying into the next session, reduce sets and load for a week before building again.

## Equipment and references

The [Candiac club page](https://www.anytimefitness.com/en-ca/locations/candiac-quebec-9900030)
lists strength and cardio equipment but no detailed machine inventory. This plan
assumes common commercial-gym equipment; every exercise includes a substitution.

The split, moderate starting volume, and effort targets are programming choices for
the assumptions above. They follow the general principles in
[ACSM's resistance-training guidance](https://acsm.org/resistance-training-guidelines-update-2026/):
train major muscle groups at least twice weekly, tailor volume to the goal, and
prioritize consistency; training to failure is not required.

File format and exercise IDs were checked against the deployed **openGym v1.3.7**
[plan importer](https://github.com/DuarteSantos8/openGym/blob/v1.3.7/frontend/src/lib/plan-share.js)
and its exercise catalogue. See also the
[openGym feature and import guide](https://opengym.duarte-santos.ch/docs.html).
