/// A category the app comes with.
typedef DefaultCategory = ({String id, String name, String keywords, String rules});

/// The categories every install starts with, in Settings order. The user can rename, change,
/// delete or restore them, and add their own.
///
/// They follow the life areas most task and time frameworks share (the American Time Use Survey's
/// activity groups, GTD's areas of focus, PARA's areas, the Wheel of Life), with work split by the
/// kind of work, since that is where a day's time mostly goes and what the statistics should tell
/// apart: organising work, doing it, and talking about it.
///
/// Their ids are fixed, so every device has the same ones without syncing anything: only the
/// user's changes to them go into the task document. Never change or reuse an id; tasks keep it.
const defaultCategories = <DefaultCategory>[
  (
    id: 'work-planning',
    name: 'Work planning',
    keywords: 'email inbox plan prepare tomorrow schedule organise weekly review kpi metrics '
        'report admin timesheet expenses priorities',
    rules: '',
  ),
  (
    id: 'focused-work',
    name: 'Focused work',
    keywords: 'write code develop design build fix bug implement analyse research draft '
        'document test deploy feature',
    rules: '',
  ),
  (
    id: 'meetings',
    name: 'Meetings and calls',
    keywords: 'meeting call standup sync presentation interview workshop client colleague '
        'team discuss demo',
    rules: '',
  ),
  (
    id: 'personal-projects',
    name: 'Personal projects',
    keywords: 'side project app website hobby blog prototype',
    rules: '',
  ),
  (
    id: 'learning',
    name: 'Learning',
    keywords: 'study learn read book course lesson practice tutorial language exam training',
    rules: '',
  ),
  (
    id: 'housekeeping',
    name: 'Housekeeping',
    keywords: 'clean tidy laundry dishes cook kitchen vacuum repair fix house garden plants '
        'trash',
    rules: '',
  ),
  (
    id: 'errands',
    name: 'Errands and shopping',
    keywords: 'buy shopping groceries store order pick up return post office supermarket '
        'pharmacy',
    rules: '',
  ),
  (
    id: 'money-paperwork',
    name: 'Money and paperwork',
    keywords: 'pay bill bank tax budget invoice insurance rent form renew contract '
        'appointment documents',
    rules: '',
  ),
  (
    id: 'workout-self-care',
    name: 'Self-care and workout',
    keywords: 'workout gym run exercise yoga walk sport stretch doctor dentist health sleep '
        'meditate rest',
    rules: '',
  ),
  (
    id: 'family-friends',
    name: 'Family and friends',
    keywords: 'family friends call visit birthday dinner partner kids parents mom dad gift',
    rules: '',
  ),
  (
    id: 'leisure',
    name: 'Leisure',
    keywords: 'fun movie game music concert travel trip holiday party relax hobby',
    rules: '',
  ),
];

/// The default category with [id], or null when it is the user's own.
DefaultCategory? defaultCategory(String id) {
  for (final c in defaultCategories) {
    if (c.id == id) return c;
  }
  return null;
}

/// A few sample tasks for each default category, which show the models what goes there. Kept
/// apart from the tasks in test/bench, so the benchmark measures what a model makes of new tasks.
const sampleTasks = <String, List<String>>{
  'work-planning': [
    'Answer work emails',
    'Plan the week',
    'Update the weekly KPI report',
    'Sort out my work to-do list',
  ],
  'focused-work': [
    'Code the new search feature',
    'Debug the payment error',
    'Write the design document',
    'Prepare the presentation for the client',
  ],
  'meetings': [
    'Weekly sync with the design team',
    'Call with the client',
    'Interview a candidate',
    'Team retrospective',
  ],
  'personal-projects': [
    'Work on my side project website',
    'Build a birdhouse',
    'Update my hobby repo on GitHub',
    'Edit my YouTube video',
  ],
  'learning': [
    'Read a chapter of the history book',
    'Online course lesson',
    'Study for the exam',
    'Language app practice',
  ],
  'housekeeping': [
    'Vacuum the living room',
    'Wash the dishes',
    'Cook dinner',
    'Fix the leaking tap',
  ],
  'errands': [
    'Pick up the parcel at the post office',
    'Grocery shopping',
    'Return the shoes to the store',
    'Get medicine at the pharmacy',
  ],
  'money-paperwork': [
    'Renew the car insurance',
    'File the tax return',
    'Transfer the rent',
    'Fill in the visa form',
  ],
  'workout-self-care': [
    'Yoga class',
    'Gym session',
    'Doctor appointment',
    'Meditate for ten minutes',
  ],
  'family-friends': [
    'Dinner with my parents',
    'Visit grandma',
    'Plan the kids\' weekend',
    'Text my best friend',
  ],
  'leisure': [
    'Play video games',
    'Go to the cinema',
    'Plan a weekend trip',
    'Read a novel',
  ],
};
