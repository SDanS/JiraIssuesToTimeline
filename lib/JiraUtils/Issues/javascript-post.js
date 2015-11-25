        for (index = 0; index < document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline').length; index++) {  
          //if (typeof document.querySelectorAll('h2.tl-headline')[index] != "undefined") {
          //  console.log(document.querySelectorAll('h2.tl-headline')[index].innerHTML);
          //}
          var colors = {
            'In Progress': 'darkcyan',
            'In Review': 'dodgerblue',
            'To Do': 'gray',
            'In Test': 'darkblue',
            'Merge Pending': 'slateblue',
            'Done': 'indigo'
          };
          if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/In Progress/mg)) {
            console.log(document.querySelectorAll('h2.tl-headline')[index].innerHTML);
            document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor = "darkcyan";
          }
          if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/In Review/mg)) {
            console.log(document.querySelectorAll('h2.tl-headline')[index].innerHTML);
            document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
              = "dodgerblue";
          }
          if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/To Do/mg)) {
            console.log(document.querySelectorAll('h2.tl-headline')[index].innerHTML);
            document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
              = "gray";
          }
          if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/In Test/mg)) {
            console.log(document.querySelectorAll('h2.tl-headline')[index].innerHTML);
            document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
              = "darkblue";
          }
          if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Merge Pending/mg)) {
            console.log(document.querySelectorAll('h2.tl-headline')[index].innerHTML);
            document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
              = "slateblue";
          }
          if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Done/mg)) {
            console.log(document.querySelectorAll('h2.tl-headline')[index].innerHTML);
            document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
              = "indigo";
          }
        
        }


        Assignee: unassigned

palevioletred: my $scope = [ 'summary', 'description', 'Story Points' ];
plum: my $misc = [ 'priority', 'issuetype' ];