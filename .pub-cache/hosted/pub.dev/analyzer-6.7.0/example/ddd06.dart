import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';

void main() async {
  var collection = AnalysisContextCollectionImpl(
    includedPaths: [
      // '/Users/scheglov/tmp/2024-06-12/scratchpad/macros_playground',
      '/Users/scheglov/tmp/2024-06-12/scratchpad/macros_playground/lib/main.dart',
      // '/Users/scheglov/dart/test/bin/test.dart',
    ],
  );

  var timer = Stopwatch()..start();
  for (var analysisContext in collection.contexts) {
    print(analysisContext.contextRoot.root.path);
    var analysisSession = analysisContext.currentSession;
    for (var path in analysisContext.contextRoot.analyzedFiles()) {
      if (path.endsWith('.dart')) {
        var libResult = await analysisSession.getResolvedLibrary(path);
        if (libResult is ResolvedLibraryResult) {
          for (var unitResult in libResult.units) {
            print('    ${unitResult.path}');
            var ep = '\n        ';
            print('      errors:$ep${unitResult.errors.join(ep)}');
            print('---');
            print(unitResult.content);
            print('---');
          }
        }
      }
    }
  }
  print('[time: ${timer.elapsedMilliseconds} ms]');

  await collection.dispose();
}
